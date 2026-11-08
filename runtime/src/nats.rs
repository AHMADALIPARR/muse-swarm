//! The zero-dependency NATS client for the Jetson nodes: the
//! owner's code, verbatim. std::net::TcpStream and
//! stack-allocated buffers only — no async runtime, no heap in
//! the hot path. The HPUB append carries the
//! Nats-Expected-Last-Sequence gate; a 'wrong last sequence'
//! -ERR is trapped as OPTIMISTIC_CONCURRENCY_REJECTED, which is
//! the runtime's signal to run the Hamiltonian escape valve.

use std::net::TcpStream;
use std::io::{Read, Write, ErrorKind};
use std::time::Duration;
use std::thread;

pub struct SovereignNatsClient {
    stream: TcpStream,
    buffer: [u8; 1024], // Static read buffer
}

impl SovereignNatsClient {
    /// Connects to BBQBADDIE with zero-dependency exponential backoff
    pub fn connect_with_backoff(addr: &str) -> Self {
        let mut delay = 10; // Start with 10ms
        let max_delay = 5000; // Cap at 5s

        loop {
            match TcpStream::connect(addr) {
                Ok(mut stream) => {
                    // Send NATS CONNECT protocol string (bare minimum for JetStream)
                    let connect_proto = b"CONNECT {\"verbose\":true,\"pedantic\":false,\"tls_required\":false,\"name\":\"jetson_orin_node\",\"protocol\":1}\r\n";
                    stream.write_all(connect_proto).expect("Failed to write CONNECT");

                    return Self {
                        stream,
                        buffer: [0; 1024],
                    };
                }
                Err(e) => {
                    // Exponential backoff
                    thread::sleep(Duration::from_millis(delay));
                    delay = (delay * 2).min(max_delay);
                }
            }
        }
    }
}

impl SovereignNatsClient {
    /// Appends the WORM block using Optimistic Concurrency (HPUB)
    pub fn append_worm_block(&mut self, subject: &str, expected_seq: u64, payload: &[u8]) -> Result<(), &'static str> {
        // 1. Format headers into a stack buffer
        let mut hdr_buf = [0u8; 128];
        let mut hdr_cursor = &mut hdr_buf[..];
        write!(hdr_cursor, "NATS/1.0\r\nNats-Expected-Last-Sequence: {}\r\n\r\n", expected_seq).unwrap();
        let hdr_bytes_written = 128 - hdr_cursor.len();
        let active_header = &hdr_buf[..hdr_bytes_written];

        // 2. Format the command into a stack buffer
        let total_bytes = hdr_bytes_written + payload.len();
        let mut cmd_buf = [0u8; 128];
        let mut cmd_cursor = &mut cmd_buf[..];
        write!(cmd_cursor, "HPUB {} {} {}\r\n", subject, hdr_bytes_written, total_bytes).unwrap();
        let cmd_bytes_written = 128 - cmd_cursor.len();
        let active_cmd = &cmd_buf[..cmd_bytes_written];

        // 3. Write directly to the TCP socket (kernel handles buffering)
        if self.stream.write_all(active_cmd).is_err() ||
           self.stream.write_all(active_header).is_err() ||
           self.stream.write_all(payload).is_err() ||
           self.stream.write_all(b"\r\n").is_err() {
            return Err("TCP_WRITE_FAILED");
        }

        // Wait for the synchronous JetStream ACK or ERR
        self.await_jetstream_ack()
    }
}

impl SovereignNatsClient {
    /// Reads the raw socket looking for the JetStream protocol response
    fn await_jetstream_ack(&mut self) -> Result<(), &'static str> {
        self.stream.set_read_timeout(Some(Duration::from_secs(2))).unwrap();

        let bytes_read = match self.stream.read(&mut self.buffer) {
            Ok(n) if n > 0 => n,
            _ => return Err("TCP_READ_FAILED"),
        };

        let response = &self.buffer[..bytes_read];

        // NATS Server accepted the WORM block
        if response.starts_with(b"+OK") {
            return Ok(());
        }

        // Optimistic Concurrency rejected the append (Sequence Mismatch)
        if response.starts_with(b"-ERR 'wrong last sequence") {
            return Err("OPTIMISTIC_CONCURRENCY_REJECTED");
        }

        // Handle native PING from NATS core to keep socket alive
        if response.starts_with(b"PING") {
            let _ = self.stream.write_all(b"PONG\r\n");
            return self.await_jetstream_ack();
        }

        Err("UNKNOWN_NATS_RESPONSE")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read as IoRead, Write as IoWrite};
    use std::net::TcpListener;

    /// A one-shot mock bus: accepts, reads the CONNECT line and
    /// one HPUB frame, hands the frame to `respond`, which
    /// drives the server side of the exchange.
    fn mock_bus<F>(respond: F) -> (u16, std::thread::JoinHandle<Vec<u8>>)
    where
        F: FnOnce(&mut TcpStream, &[u8]) + Send + 'static,
    {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let handle = std::thread::spawn(move || {
            let (mut sock, _) = listener.accept().unwrap();
            let mut all = Vec::new();
            let mut chunk = [0u8; 512];
            // read CONNECT line + HPUB frame (ends with the
            // payload's trailing CRLF)
            let payload_tail: &[u8] = &[1, 2, 3, 4, b'\r', b'\n'];
            while !all.windows(payload_tail.len()).any(|w| w == payload_tail) {
                let n = sock.read(&mut chunk).unwrap();
                assert!(n > 0, "socket closed early");
                all.extend_from_slice(&chunk[..n]);
            }
            respond(&mut sock, &all);
            all
        });
        (port, handle)
    }

    #[test]
    fn append_ok_and_frame_shape() {
        let (port, server) = mock_bus(|sock, _frame| {
            sock.write_all(b"+OK\r\n").unwrap();
        });
        let mut client = SovereignNatsClient::connect_with_backoff(&format!("127.0.0.1:{}", port));
        let r = client.append_worm_block("sovereign.ledger.append", 42, &[1, 2, 3, 4]);
        assert_eq!(r, Ok(()));
        let frame = server.join().unwrap();
        let text = String::from_utf8_lossy(&frame);
        assert!(text.contains("CONNECT {\"verbose\":true"), "CONNECT first: {}", text);
        assert!(text.contains("HPUB sovereign.ledger.append 45 49\r\n"), "HPUB two-number form: {}", text);
        assert!(text.contains("NATS/1.0\r\nNats-Expected-Last-Sequence: 42\r\n\r\n"), "gate header: {}", text);
    }

    #[test]
    fn wrong_last_sequence_is_trapped() {
        let (port, server) = mock_bus(|sock, _frame| {
            sock.write_all(b"-ERR 'wrong last sequence'\r\n").unwrap();
        });
        let mut client = SovereignNatsClient::connect_with_backoff(&format!("127.0.0.1:{}", port));
        let r = client.append_worm_block("sovereign.ledger.append", 42, &[1, 2, 3, 4]);
        assert_eq!(r, Err("OPTIMISTIC_CONCURRENCY_REJECTED"));
        let _ = server.join().unwrap();
    }

    #[test]
    fn ping_is_ponged_then_ok() {
        let (port, server) = mock_bus(|sock, _frame| {
            sock.write_all(b"PING\r\n").unwrap();
            let mut pong = [0u8; 6];
            sock.read_exact(&mut pong).unwrap();
            assert_eq!(&pong, b"PONG\r\n");
            sock.write_all(b"+OK\r\n").unwrap();
        });
        let mut client = SovereignNatsClient::connect_with_backoff(&format!("127.0.0.1:{}", port));
        let r = client.append_worm_block("sovereign.ledger.append", 42, &[1, 2, 3, 4]);
        assert_eq!(r, Ok(()));
        let _ = server.join().unwrap();
    }
}
