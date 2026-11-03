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
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.simulation.Simulation;

/**
 * Code checks (S10, 3 Nov 2026), items 2 and 3: facts of the code that need no batch.
 *
 * @author Leonard Stellbrink
 */
public class CodeFactsTest {

    /**
     * Item 2: neither Agent nor GraphStream's node classes (SingleNode, AdjacencyListNode,
     * AbstractNode, AbstractElement; gs-core 1.3) override hashCode or equals, so the HashSets in
     * Simulation.computeAgentDynamics() (Simulation.java:363-364) order agents by
     * Object.hashCode(), the identity hash.
     */
    @Test
    public void testAgentHashCodeAndEqualsAreObjects() throws NoSuchMethodException {
        assertEquals(Object.class, Agent.class.getMethod("hashCode").getDeclaringClass());
        assertEquals(Object.class, Agent.class.getMethod("equals", Object.class).getDeclaringClass());
    }

    /**
     * Item 3: the burn-in (Simulation.simulateUntilStable(zeta), called by
     * NunnerBuskensDataGenerator.simulatePreEpidemic(), :556) runs exactly zeta time steps: it
     * sets rounds = 1 (Simulation.java:205), loops while rounds <= zeta (:208) and computeSingleRound
     * counts up (:307), and the network never reports stable, because computeStability() is never
     * called (Network.java:2142 and :2152 commented out) and only it raises TIMESTEPS_STABLE
     * (:1893) from its start value -1 (:157).
     */
    @Test
    public void testBurnInRunsZetaStepsAndIsNeverStable() {
        int zeta = MainDesignNetwork.params().getZeta();
        assertEquals("committed config: zeta", 10, zeta);
        MainDesignNetwork md = MainDesignNetwork.build(40, 0.5);
        assertFalse(md.network.isStable());
        Simulation simulation = new Simulation(md.network, false);
        simulation.simulateUntilStable(zeta);
        assertEquals("rounds counter after the burn-in: zeta steps run", zeta + 1, simulation.getRounds());
        assertFalse(md.network.isStable());
        assertTrue("TIMESTEPS_STABLE never raised", md.network.getTimestepsStable() <= 0);
    }
}
