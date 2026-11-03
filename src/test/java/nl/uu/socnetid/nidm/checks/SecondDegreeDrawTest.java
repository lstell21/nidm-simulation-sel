/*
 * Copyright (C) 2026
 *      Leonard Stellbrink
 *
 * This file is part of the NIDM-Simulation project <https://github.com/hnunner/NIDM-simulation>.
 *
 * This program is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software Foundation,
 * either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program.
 * If not, see <http://www.gnu.org/licenses/>.
 */
package nl.uu.socnetid.nidm.checks;

import static org.junit.Assert.assertEquals;

import java.util.List;
import java.util.Locale;

import org.junit.Test;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.utility.NunnerBuskens;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * Code checks (S10, 3 Nov 2026), item 1: second-degree neighbours are listed once per shared
 * neighbour (Agent.getConnectionsAtDistance2(), Agent.java:575-596 at 490a1c7), and the shuffled
 * branch of Agent.computeRound draws from that list as it is (:1067-1068 shuffle it, :1149 takes
 * the first element), so an agent reachable through k shared neighbours is drawn k times as often
 * as one reachable through one. The sorted branch (omega = 1; :1065-1066, sorted by risk-perception
 * difference) takes the most similar agent whatever its multiplicity.
 *
 * Network: x - n1, n2, n3; a - n1; b - n1, n2; c - n1, n2, n3. So a, b, c are at distance 2 from x
 * through 1, 2 and 3 shared neighbours. x decides once per round (phi = 1/6, 7 agents: round(6 * 1/6)
 * = 1), always from the distance-2 pool (psi = 0, xi = 1), and every tie is worth forming for
 * everyone here (b1 = 1 > c1 + c2 (2 deg - 1) up to degree 7, no triad term), so x ties to exactly
 * the agent it drew: the draw is observed through the decision, not re-implemented.
 *
 * @author Leonard Stellbrink
 */
public class SecondDegreeDrawTest {

    private static final int REPS = 6000;

    private Agent x;
    private Agent a;
    private Agent b;
    private Agent c;

    private void build(double omega) {
        Network network = new Network();
        UtilityFunction uf = new NunnerBuskens(1.0, 0.0, 0.5, 0.2, 0.05, 0.5);
        DiseaseSpecs ds = new DiseaseSpecs(DiseaseType.SIR, 5, 2.0, 0.1, 0.0);
        double phi = 1.0 / 6.0;
        // risk perceptions: a is the most similar to x, c the least
        this.x = network.addAgent(uf, ds, 1.0, 1.0, phi, omega, false, 0.0, 1.0, 30, false, "NA", false, false);
        Agent n1 = network.addAgent(uf, ds, 1.0, 1.0, phi, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        Agent n2 = network.addAgent(uf, ds, 1.0, 1.0, phi, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        Agent n3 = network.addAgent(uf, ds, 1.0, 1.0, phi, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.a = network.addAgent(uf, ds, 1.1, 1.1, phi, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.b = network.addAgent(uf, ds, 1.5, 1.5, phi, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.c = network.addAgent(uf, ds, 1.9, 1.9, phi, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.x.addConnection(n1);
        this.x.addConnection(n2);
        this.x.addConnection(n3);
        this.a.addConnection(n1);
        this.b.addConnection(n1);
        this.b.addConnection(n2);
        this.c.addConnection(n1);
        this.c.addConnection(n2);
        this.c.addConnection(n3);
    }

    private static int count(List<Agent> list, Agent agent) {
        int k = 0;
        for (Agent other : list) {
            if (other == agent) {
                k++;
            }
        }
        return k;
    }

    /** The list holds each second-degree neighbour once per shared neighbour. */
    @Test
    public void testListHoldsOneEntryPerSharedNeighbour() {
        build(0.0);
        List<Agent> dist2 = this.x.getConnectionsAtDistance2();
        StringBuilder ids = new StringBuilder();
        for (Agent agent : dist2) {
            ids.append(agent == this.a ? "a" : agent == this.b ? "b" : agent == this.c ? "c" : "?").append(' ');
        }
        System.out.println("getConnectionsAtDistance2() of x: [ " + ids + "]");
        assertEquals(6, dist2.size());
        assertEquals(1, count(dist2, this.a));
        assertEquals(2, count(dist2, this.b));
        assertEquals(3, count(dist2, this.c));
    }

    /**
     * Shuffled branch (omega = 0): a, b, c are drawn in proportion 1 : 2 : 3. Sorted branch
     * (omega = 1): always a, the most similar, although it has the fewest entries.
     */
    @Test
    public void testDrawProbabilities() {
        int[] shuffled = draws(0.0);
        int[] sorted = draws(1.0);
        System.out.println(String.format(Locale.ROOT, "draws in %d rounds of x    a      b      c      expected (shuffled 1:2:3)", REPS));
        System.out.println(String.format(Locale.ROOT, "  shuffled (omega = 0)  %.3f  %.3f  %.3f  0.167  0.333  0.500",
                shuffled[0] / (double) REPS, shuffled[1] / (double) REPS, shuffled[2] / (double) REPS));
        System.out.println(String.format(Locale.ROOT, "  sorted   (omega = 1)  %.3f  %.3f  %.3f  (most similar first: a)",
                sorted[0] / (double) REPS, sorted[1] / (double) REPS, sorted[2] / (double) REPS));
        // 6,000 draws: standard error <= 0.0065; 0.03 is more than four of them
        assertEquals(1.0 / 6.0, shuffled[0] / (double) REPS, 0.03);
        assertEquals(2.0 / 6.0, shuffled[1] / (double) REPS, 0.03);
        assertEquals(3.0 / 6.0, shuffled[2] / (double) REPS, 0.03);
        assertEquals(REPS, sorted[0]);
    }

    private int[] draws(double omega) {
        int[] counts = new int[3];
        for (int rep = 0; rep < REPS; rep++) {
            build(omega);
            this.x.computeRound();
            int ties = 0;
            if (this.x.isDirectlyConnectedTo(this.a)) {
                counts[0]++;
                ties++;
            }
            if (this.x.isDirectlyConnectedTo(this.b)) {
                counts[1]++;
                ties++;
            }
            if (this.x.isDirectlyConnectedTo(this.c)) {
                counts[2]++;
                ties++;
            }
            assertEquals("x forms exactly one tie per round", 1, ties);
        }
        return counts;
    }
}
