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

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Test;

import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.stats.LocalAgentConnectionsStats;
import nl.uu.socnetid.nidm.stats.StatsComputer;
import nl.uu.socnetid.nidm.utility.NunnerBuskens;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * Edge ids and tie lookups (S7b). Until rerun-fixes an edge id concatenated the two agent ids
 * without a separator, so the pairs 1-112 and 11-12 shared the id "1112": while one of them was
 * tied, the other counted as tied, could not form, and two neighbours 11 and 12 of a third agent
 * counted as a closed triad. Edge ids are now "lower id-higher id", and ties are looked up by
 * adjacency.
 *
 * @author Leonard Stellbrink
 */
public class AgentEdgeIdTest {

    private static final int N = 120;

    private Network network;
    private Agent[] agents;


    /**
     * Performed before each test: 120 agents, no ties.
     */
    @Before
    public void initNetwork() {
        this.network = new Network("Edge id test");
        UtilityFunction uf = new NunnerBuskens(1.0, 0.5, 0.5, 0.2, 0.05, 0.5);
        DiseaseSpecs ds = new DiseaseSpecs(DiseaseType.SIR, 5, 2.0, 0.15, 0.0);
        this.agents = new Agent[N + 1];
        for (int id = 1; id <= N; id++) {
            this.agents[id] = this.network.addAgent(uf, ds);
        }
    }

    /**
     * The couple 1-112 and 11-12 gives two different ids, lower id first, with a separator.
     */
    @Test
    public void testEdgeIdsWithSeparator() {
        this.agents[112].addConnection(this.agents[1]);
        this.agents[11].addConnection(this.agents[12]);
        String id1 = this.agents[1].getEdgeBetween(this.agents[112]).getId();
        String id2 = this.agents[11].getEdgeBetween(this.agents[12]).getId();
        assertEquals("1-112", id1);
        assertEquals("11-12", id2);
        assertNotEquals(id1, id2);
        assertEquals(2, this.network.getEdgeCount());
    }

    /**
     * With 1-112 tied, 11 and 12 are not tied, a tie 11-12 can form, and removing it leaves 1-112.
     */
    @Test
    public void testCollidingPairsIndependent() {
        this.agents[1].addConnection(this.agents[112]);
        assertFalse(this.agents[11].isDirectlyConnectedTo(this.agents[12]));
        assertFalse(this.agents[12].isDirectlyConnectedTo(this.agents[11]));

        this.agents[11].addConnection(this.agents[12]);
        assertTrue(this.agents[11].isDirectlyConnectedTo(this.agents[12]));
        assertTrue(this.agents[1].isDirectlyConnectedTo(this.agents[112]));
        assertEquals(2, this.network.getEdgeCount());

        this.agents[12].removeConnection(this.agents[11]);
        assertFalse(this.agents[11].isDirectlyConnectedTo(this.agents[12]));
        assertTrue(this.agents[1].isDirectlyConnectedTo(this.agents[112]));
        assertEquals(1, this.network.getEdgeCount());
    }

    /**
     * An agent with the neighbours 11 and 12 (not tied to each other) has one open and no closed
     * triad, with or without the tie 1-112; its utility does not change either.
     */
    @Test
    public void testTriadCountUnchangedByCollidingTie() {
        Agent agent = this.agents[50];
        agent.addConnection(this.agents[11]);
        agent.addConnection(this.agents[12]);
        LocalAgentConnectionsStats before = StatsComputer.computeLocalAgentConnectionsStats(agent);
        double utilityBefore = agent.getUtility().getOverallUtility();
        assertEquals(1, before.getY());
        assertEquals(0, before.getZ());

        this.agents[1].addConnection(this.agents[112]);
        LocalAgentConnectionsStats after = StatsComputer.computeLocalAgentConnectionsStats(agent);
        assertEquals(1, after.getY());
        assertEquals(0, after.getZ());
        assertEquals(utilityBefore, agent.getUtility().getOverallUtility(), 0.0);
        assertFalse(agent.isConnectedToAtDistance2(this.agents[112]));
    }

    /**
     * Edges with ids in the old format (as in DGS files written before rerun-fixes) are still
     * found and removed: lookups go by adjacency, not by id.
     */
    @Test
    public void testOldFormatEdgeIdsStillWork() {
        this.network.addEdge("1112", "11", "12");
        assertTrue(this.agents[11].isDirectlyConnectedTo(this.agents[12]));
        assertFalse(this.agents[1].isDirectlyConnectedTo(this.agents[112]));
        // the old-format edge blocks no new tie
        this.agents[1].addConnection(this.agents[112]);
        assertTrue(this.agents[1].isDirectlyConnectedTo(this.agents[112]));
        this.agents[11].removeConnection(this.agents[12]);
        assertNull(this.network.getEdge("1112"));
        assertTrue(this.agents[1].isDirectlyConnectedTo(this.agents[112]));
    }

}
