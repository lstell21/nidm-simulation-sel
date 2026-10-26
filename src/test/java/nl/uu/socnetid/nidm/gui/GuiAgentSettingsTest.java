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
package nl.uu.socnetid.nidm.gui;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.HashSet;
import java.util.Set;

import org.junit.Test;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.utility.NunnerBuskens;

/**
 * Tests that the GUI's agent and NunnerBuskens settings reach the agents and the utility function
 * (AgentSettings, SharedUtilityPanel.getAgentSettings, NunnerBuskensPanel.createUtilityFunction).
 * No window is opened.
 *
 * @author Leonard Stellbrink
 */
public class GuiAgentSettingsTest {

    private static final double EPS = 1e-12;

    private static DiseaseSpecs diseaseSpecs() {
        return new DiseaseSpecs(DiseaseType.SIR, 5, 2.0, 0.4, 0.0);
    }

    /**
     * Manual settings: selective, psi, xi, phi, omega and both risk perceptions reach the agent.
     */
    @Test
    public void testManualSettingsReachAgent() {
        Network network = new Network();
        NunnerBuskens uf = new NunnerBuskens(1.0, 0.5, 0.45, 0.2, 0.05, 0.5);

        Agent selective = new AgentSettings(AgentSettings.RiskPerception.MANUAL, 1.2, 0.8, 0.2025, 0.5,
                true, 0.4, 0.2).addAgent(network, uf, diseaseSpecs());
        assertTrue(selective.isSelective());
        assertEquals(0.4, selective.getPsi(), EPS);
        assertEquals(0.2, selective.getXi(), EPS);
        assertEquals(0.2025, selective.getPhi(), EPS);
        assertEquals(0.5, selective.getOmega(), EPS);
        assertEquals(1.2, selective.getRSigma(), EPS);
        assertEquals(0.8, selective.getRPi(), EPS);

        Agent random = new AgentSettings(AgentSettings.RiskPerception.MANUAL, 1.0, 1.0, 0.2, 0.0,
                false, 0.3, 0.1).addAgent(network, uf, diseaseSpecs());
        assertFalse(random.isSelective());
        assertEquals(0.3, random.getPsi(), EPS);
        assertEquals(0.1, random.getXi(), EPS);
        assertEquals(2, network.getAgents().size());
    }

    /**
     * Risk perception as in the batches: r in [0.447402, 2.0], r_sigma == r_pi, and r varies.
     */
    @Test
    public void testBatchRiskPerception() {
        Network network = new Network();
        NunnerBuskens uf = new NunnerBuskens(1.0, 0.5, 0.45, 0.2, 0.05, 0.5);
        AgentSettings settings = new AgentSettings(AgentSettings.RiskPerception.BATCH, 1.0, 1.0, 0.2, 0.5,
                true, 0.4, 0.2);
        Set<Double> values = new HashSet<Double>();
        double sum = 0.0;
        int n = 2000;
        for (int i = 0; i < n; i++) {
            Agent agent = settings.addAgent(network, uf, diseaseSpecs());
            double r = agent.getRSigma();
            assertTrue("r below 0.447402: " + r, r >= BatchRiskPerception.MIN);
            assertTrue("r above 2.0: " + r, r <= BatchRiskPerception.MAX);
            assertEquals(r, agent.getRPi(), 0.0);
            values.add(r);
            sum += r;
        }
        assertTrue(values.size() > n / 2);
        // mean of N(1.223701, 0.4625078) truncated to [0.447402, 2.0] is about 1.22
        assertEquals(1.22, sum / n, 0.05);
    }

    /**
     * The panels: defaults, set values, and d reaching the utility function, also while it runs.
     */
    @Test
    public void testPanelsMapToAgentAndUtilityFunction() {
        NunnerBuskensPanel panel = new NunnerBuskensPanel();

        // defaults: selective off, psi 0.40, xi 0.20 (Table 1), random risk perception, d 0.5
        AgentSettings defaults = panel.getAgentSettings();
        assertFalse(defaults.isSelective());
        assertEquals(0.4, defaults.getPsi(), EPS);
        assertEquals(0.2, defaults.getXi(), EPS);
        assertEquals(AgentSettings.RiskPerception.RANDOM, defaults.getRiskPerception());
        assertEquals(0.5, panel.getD(), EPS);

        // set values reach the settings and the agent
        panel.setContactSettings(true, 0.3, 0.1);
        panel.setRiskPerception(AgentSettings.RiskPerception.BATCH);
        AgentSettings settings = panel.getAgentSettings();
        assertTrue(settings.isSelective());
        assertEquals(0.3, settings.getPsi(), EPS);
        assertEquals(0.1, settings.getXi(), EPS);
        assertEquals(AgentSettings.RiskPerception.BATCH, settings.getRiskPerception());

        NunnerBuskens uf = panel.createUtilityFunction();
        assertEquals(0.5, uf.getD(), EPS);
        Agent agent = settings.addAgent(new Network(), uf, diseaseSpecs());
        assertTrue(agent.isSelective());
        assertEquals(0.3, agent.getPsi(), EPS);
        assertEquals(0.1, agent.getXi(), EPS);
        assertEquals(agent.getRSigma(), agent.getRPi(), 0.0);
        assertEquals(0.5, ((NunnerBuskens) agent.getUtilityFunction()).getD(), EPS);

        // d changed in the panel reaches the existing utility function and new ones
        panel.setD(0.8);
        assertEquals(0.8, uf.getD(), EPS);
        assertEquals(0.8, panel.createUtilityFunction().getD(), EPS);
    }

}
