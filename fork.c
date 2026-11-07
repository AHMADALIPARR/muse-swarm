/* fork - the typed-decision fork layer of the muse-swarm.
 *
 * Reads proposals on stdin, one per line:
 *
 *     <decision-name> <confidence>
 *
 * and emits one verdict line per proposal on stdout:
 *
 *     verdict <decision-name> p=<confidence> SHARP|SPLIT
 *
 * SHARP (confidence >= THRESHOLD) runs in code: the decision is taken
 * as-is, no model is consulted again. SPLIT escalates to the lead.
 * This is the abstain-on-low-confidence rule of the typed-decision
 * engine (zero-token, zt_core.h) expressed as a router: a decision
 * the swarm is sure of is a verdict; a decision it is split on is a
 * proposal to the lead, never a coin flip.
 *
 * Exit status: 0 when every input line parsed, 2 on a malformed line.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define THRESHOLD 0.80

int main(void) {
    char line[512];
    int bad = 0;
    while (fgets(line, sizeof line, stdin)) {
        char name[128];
        double p;
        char extra;
        if (sscanf(line, "%127s %lf %c", name, &p, &extra) != 2) {
            if (line[0] == '\n' || line[0] == '\0') continue;
            fprintf(stderr, "fork: malformed line: %s", line);
            bad = 1;
            continue;
        }
        if (p < 0.0 || p > 1.0) {
            fprintf(stderr, "fork: confidence out of range: %s", line);
            bad = 1;
            continue;
        }
        printf("verdict %s p=%.2f %s\n", name, p, p >= THRESHOLD ? "SHARP" : "SPLIT");
        fflush(stdout);
    }
    return bad ? 2 : 0;
}
