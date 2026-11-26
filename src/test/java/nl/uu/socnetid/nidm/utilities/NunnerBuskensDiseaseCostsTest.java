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
package nl.uu.socnetid.nidm.utilities;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.utility.InfectedCostCheck;
import nl.uu.socnetid.nidm.utility.NunnerBuskens;
import nl.uu.socnetid.nidm.utility.Utility;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * Disease costs of {@link NunnerBuskens} (manuscript Eq. 5) and the shadow check
 * {@link InfectedCostCheck}: an infected agent's disease cost is sigma for every d; a susceptible
 * agent's is d * local + (1 - d) * global.
 *
 * Network (agents 1-6): 1 - 2, 1 - 3, 2 - 3, 2 - 4, 4 - 5; agent 6 isolated. Agents 1 and 5 are
 * infected, so the prevalence is 2/6 and agent 2 has three ties, one of them to an infected agent.
 *
 * @author Leonard Stellbrink
 */
public class NunnerBuskensDiseaseCostsTest {

    private static final double[] DS = {0.0, 0.5, 1.0};

    private static final double b1      = 1.0;
    private static final double b2      = 0.5;
    private static final double alpha   = 0.5;
    private static final double c1      = 0.2;
    private static final double c2      = 0.05;
    private static final double sigma   = 2.3;
    private static final double gamma   = 0.15;
    private static final int    tau     = 5;
    private static final double rSigma  = 1.3;
    private static final double rPi     = 0.7;
    private static final double phi     = 0.4;
    private static final double omega   = 0.0;

    private DiseaseSpecs ds;
    private Network network;
    private Agent infected;
    private Agent susceptible;
    private Agent agent3;
    private Agent agent4;
    private Agent agent6;

    private UtilityFunction buildNetwork(double d) {
        this.ds = new DiseaseSpecs(DiseaseType.SIR, tau, sigma, gamma, 0);
        UtilityFunction uf = new NunnerBuskens(b1, b2, alpha, c1, c2, d);
        this.network = new Network("NunnerBuskens disease costs test");
        this.infected = this.network.addAgent(uf, this.ds, rSigma, rPi, phi, omega);
        this.susceptible = this.network.addAgent(uf, this.ds, rSigma, rPi, phi, omega);
        this.agent3 = this.network.addAgent(uf, this.ds, rSigma, rPi, phi, omega);
        this.agent4 = this.network.addAgent(uf, this.ds, rSigma, rPi, phi, omega);
        Agent agent5 = this.network.addAgent(uf, this.ds, rSigma, rPi, phi, omega);
        this.agent6 = this.network.addAgent(uf, this.ds, rSigma, rPi, phi, omega);
        this.infected.addConnection(this.susceptible);
        this.infected.addConnection(this.agent3);
        this.susceptible.addConnection(this.agent3);
        this.susceptible.addConnection(this.agent4);
        this.agent4.addConnection(agent5);
        this.infected.forceInfect(this.ds);
        agent5.forceInfect(this.ds);
        return uf;
    }

    /**
     * An infected agent's disease cost is sigma, whatever d and whatever its ties.
     */
    @Test
    public void testInfectedAgentCostIsSigma() {
        for (double d : DS) {
            buildNetwork(d);
            assertEquals("d = " + d, sigma, this.infected.getUtility().getDiseaseCosts(), 0.0);
            // with one tie more and one tie less
            this.infected.addConnection(this.agent6);
            assertEquals("d = " + d, sigma, this.infected.getUtility().getDiseaseCosts(), 0.0);
            this.infected.removeConnection(this.agent6);
            this.infected.removeConnection(this.agent3);
            assertEquals("d = " + d, sigma, this.infected.getUtility().getDiseaseCosts(), 0.0);
        }
    }

    /**
     * A susceptible agent's disease cost is unchanged: d * local + (1 - d) * global.
     */
    @Test
    public void testSusceptibleAgentCostUnchanged() {
        // agent 2: n = 3 ties, nI = 1 of them infected; prevalence 2/6
        double local = Math.pow(1 - Math.pow(1 - gamma, 1), 2 - rPi) * Math.pow(sigma, rSigma);
        double global = Math.pow(1 - Math.pow(1 - (2.0 / 6.0) * gamma, 3), 2 - rPi) * Math.pow(sigma, rSigma);
        for (double d : DS) {
            buildNetwork(d);
            assertEquals("d = " + d, d * local + (1 - d) * global,
                    this.susceptible.getUtility().getDiseaseCosts(), 1e-12);
        }
    }

    /**
     * The shadow check's old cost: d * sigma for an infected agent, the current cost otherwise.
     */
    @Test
    public void testOverallUtilityOldInfectedCosts() {
        for (double d : DS) {
            UtilityFunction uf = buildNetwork(d);
            Utility u = this.infected.getUtility();
            assertEquals("d = " + d, u.getSocialBenefits() - u.getSocialCosts() - d * sigma,
                    uf.getOverallUtilityOldInfectedCosts(u, this.infected), 0.0);
            Utility s = this.susceptible.getUtility();
            assertEquals("d = " + d, s.getOverallUtility(), uf.getOverallUtilityOldInfectedCosts(s, this.susceptible), 0.0);
        }
    }

    /**
     * The shadow check counts every tie decision of an infected agent (requesting, accepting,
     * cutting), none of a susceptible agent, and changes no decision.
     */
    @Test
    public void testInfectedCostCheckCountsAndChangesNothing() {
        for (double d : DS) {
            buildNetwork(d);
            boolean valuable = this.infected.newConnectionValuable(this.agent6);
            boolean tooCostly = this.infected.existingConnectionTooCostly(this.agent3);
            boolean susceptibleValuable = this.susceptible.newConnectionValuable(this.agent6);

            InfectedCostCheck check = new InfectedCostCheck();
            this.network.setInfectedCostCheck(check);
            assertEquals(valuable, this.infected.newConnectionValuable(this.agent6));
            assertEquals(tooCostly, this.infected.existingConnectionTooCostly(this.agent3));
            assertEquals(susceptibleValuable, this.susceptible.newConnectionValuable(this.agent6));
            assertEquals("d = " + d, 2, check.getN());
            // agent 6 requests a tie with agent 1, which is infected and decides on accepting it
            this.agent6.connectTo(this.infected);
            assertEquals("d = " + d, 3, check.getN());
            // the cost of an infected agent does not depend on its ties: no decision changes
            assertEquals("d = " + d, 0, check.getDiff());
        }
    }

}
