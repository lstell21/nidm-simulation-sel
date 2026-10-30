/*
 * Copyright (C) 2026
 *      Leonard Stellbrink
 *
 * This file is part of the NIDM-Simulation project <https://github.com/hnunner/NIDM-simulation>.
 *
 * This project is a stand-alone Java program of the Networking during Infectious Diseases Model
 * (NIDM; Nunner, Buskens, & Kretzschmar, 2019) to simulate the dynamic interplay of social network
 * formation and infectious diseases.
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
 *
 * References:
 *      Nunner, H., Buskens, V., & Kretzschmar, M. (2019). A model for the co-evolution of dynamic
 *      social networks and infectious diseases. Manuscript sumbitted for publication.
 */
package nl.uu.socnetid.nidm.agents;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.utility.NunnerBuskens;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * The peer pools of Agent.computeRound (Agent.java:1087, fixed on rerun-fixes; test from the bug
 * check S6, branch bugfix-1087-test). The pools are local to computeRound, so they are observed
 * through the decisions: on the path A - B - C - D, B is a
 * direct contact of A, C a second-degree neighbour and D at distance 3. A tie is worth forming
 * for every agent here, so A forms a tie with every agent it draws that it is not yet tied to.
 *
 * With psi = xi = 0 every decision draws from the "all other agents" pool: the shuffled one if
 * omega = 0 (randOmega > omega), the assorted one if omega = 1. Both must contain neither direct
 * contacts nor second-degree neighbours, so A ties to D but never to C. Before the fix, the
 * shuffled pool kept the second-degree neighbours, and A tied to C. With psi = 0 and xi = 1
 * every decision draws from the distance-2 pool, which must still contain C (shuffled and
 * assorted pools of the other categories unchanged).
 *
 * @author Leonard Stellbrink
 */
public class AgentDecisionPoolTest {

    private static final int ROUNDS = 25;

    private Agent a;
    private Agent b;
    private Agent c;
    private Agent d;

    /**
     * Builds the path A - B - C - D; only A's settings matter, only A decides.
     */
    private void buildPath(double omega, double psi, double xi) {
        Network network = new Network();
        // ties worth forming at these degrees (b1 > c1 + c2 (2n - 1)); no triad term
        UtilityFunction uf = new NunnerBuskens(1.0, 0.0, 0.5, 0.2, 0.05, 0.5);
        DiseaseSpecs ds = new DiseaseSpecs(DiseaseType.SIR, 5, 2.0, 0.1, 0.0);
        // phi = 1.0: round((N - 1) * phi) = 3 decisions per round for A
        this.a = network.addAgent(uf, ds, 1.0, 1.0, 1.0, omega, false, psi, xi, 30, false, "NA", false, false);
        this.b = network.addAgent(uf, ds, 1.0, 1.0, 1.0, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.c = network.addAgent(uf, ds, 1.0, 1.0, 1.0, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.d = network.addAgent(uf, ds, 1.0, 1.0, 1.0, 0.0, false, 0.4, 0.2, 30, false, "NA", false, false);
        this.a.addConnection(this.b);
        this.b.addConnection(this.c);
        this.c.addConnection(this.d);
    }

    /**
     * Shuffled "all other agents" pool (non-assorted branch): no direct contacts, no
     * second-degree neighbours.
     */
    @Test
    public void testRandomOthersPoolExcludesFirstAndSecondDegree() {
        buildPath(0.0, 0.0, 0.0);
        for (int i = 0; i < ROUNDS; i++) {
            this.a.computeRound();
            assertFalse("A drew its second-degree neighbour C from the random-others pool",
                    this.a.isDirectlyConnectedTo(this.c));
            assertTrue("A drew its direct contact B from the random-others pool and dropped it",
                    this.a.isDirectlyConnectedTo(this.b));
        }
        assertTrue("A never drew D (distance 3) from the random-others pool", this.a.isDirectlyConnectedTo(this.d));
    }

    /**
     * Assorted "all other agents" pool: unchanged, no direct contacts, no second-degree
     * neighbours.
     */
    @Test
    public void testAssortedOthersPoolExcludesFirstAndSecondDegree() {
        buildPath(1.0, 0.0, 0.0);
        for (int i = 0; i < ROUNDS; i++) {
            this.a.computeRound();
            assertFalse(this.a.isDirectlyConnectedTo(this.c));
            assertTrue(this.a.isDirectlyConnectedTo(this.b));
        }
        assertTrue(this.a.isDirectlyConnectedTo(this.d));
    }

    /**
     * Distance-2 pools, shuffled and assorted: unchanged, they still hold the second-degree
     * neighbours.
     */
    @Test
    public void testDistance2PoolsStillHoldSecondDegree() {
        for (double omega : new double[] {0.0, 1.0}) {
            buildPath(omega, 0.0, 1.0);
            // the first decision draws from the distance-2 pool; once it is used up, later
            // decisions in the round fall through to the "all other agents" pool (D)
            this.a.computeRound();
            assertTrue("omega " + omega + ": A did not draw C from the distance-2 pool",
                    this.a.isDirectlyConnectedTo(this.c));
        }
    }

}
