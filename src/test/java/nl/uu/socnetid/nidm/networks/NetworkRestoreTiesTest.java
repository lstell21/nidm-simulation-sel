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
package nl.uu.socnetid.nidm.networks;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.List;

import org.junit.Before;
import org.junit.Test;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.utility.Cumulative;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * Paired design (nb.ep.structure=both): {@link Network#restoreTies(List)} reproduces a recorded tie
 * list, so the adapting arm starts from the network the frozen arm started from.
 *
 * Edge ids concatenate the two agent ids without a separator, so the ties 1 - 112 and 11 - 12
 * share the id "1112". The test records 1 - 112 and replaces it by 11 - 12 before restoring.
 *
 * @author Leonard Stellbrink
 */
public class NetworkRestoreTiesTest {

    private static final int N = 120;

    private Network network;
    private Agent[] agents;


    /**
     * Performed before each test: 120 agents, eight ties.
     */
    @Before
    public void initNetwork() {
        this.network = new Network("Restore ties test");
        UtilityFunction uf = new Cumulative();
        DiseaseSpecs ds = new DiseaseSpecs(DiseaseType.SIR, 10, 8.4, 0.1, 2.5);
        this.agents = new Agent[N + 1];
        for (int id = 1; id <= N; id++) {
            this.agents[id] = this.network.addAgent(uf, ds);
        }
        connect(1, 2);
        connect(2, 3);
        connect(3, 4);
        connect(112, 1);
        connect(5, 60);
        connect(90, 30);
        connect(100, 120);
        connect(11, 13);
    }

    private void connect(int id1, int id2) {
        this.agents[id1].addConnection(this.agents[id2]);
    }

    private static List<String> asStrings(List<long[]> ties) {
        List<String> strings = new ArrayList<String>(ties.size());
        for (long[] tie : ties) {
            strings.add(tie[0] + "-" + tie[1]);
        }
        return strings;
    }

    /**
     * Ties come as pairs of agent ids, the lower id first, sorted numerically.
     */
    @Test
    public void testGetTies() {
        List<String> expected = new ArrayList<String>();
        expected.add("1-2");
        expected.add("1-112");
        expected.add("2-3");
        expected.add("3-4");
        expected.add("5-60");
        expected.add("11-13");
        expected.add("30-90");
        expected.add("100-120");
        assertEquals(expected, asStrings(this.network.getTies()));
    }

    /**
     * After ties were cut and formed, restoring the recorded list reproduces it exactly, and the
     * edge-list hash equals the recorded one again.
     */
    @Test
    public void testRestoreTiesReproducesRecordedTies() {
        List<long[]> recorded = this.network.getTies();
        String recordedHash = this.network.getEdgeListHash();

        // tie revisions as after the frozen arm: two ties cut, three formed
        this.agents[1].removeConnection(this.agents[112]);
        this.agents[3].removeConnection(this.agents[2]);
        connect(11, 12);
        connect(7, 8);
        connect(60, 61);
        assertNotEquals(recordedHash, this.network.getEdgeListHash());

        this.network.restoreTies(recorded);

        assertEquals(asStrings(recorded), asStrings(this.network.getTies()));
        assertEquals(recordedHash, this.network.getEdgeListHash());
        assertTrue(this.agents[1].hasEdgeBetween(this.agents[112]));
        assertFalse(this.agents[11].hasEdgeBetween(this.agents[12]));
        assertEquals(recorded.size(), this.network.getEdgeCount());
    }

    /**
     * Restoring the current tie list changes nothing.
     */
    @Test
    public void testRestoreTiesUnchanged() {
        List<long[]> recorded = this.network.getTies();
        String recordedHash = this.network.getEdgeListHash();
        this.network.restoreTies(recorded);
        assertEquals(asStrings(recorded), asStrings(this.network.getTies()));
        assertEquals(recordedHash, this.network.getEdgeListHash());
    }

}
