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

import java.util.concurrent.ThreadLocalRandom;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.data.in.AgeStructure;
import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * The agent settings of a utility panel (SharedUtilityPanel.getAgentSettings), and how the GUI
 * turns them into a new agent. Kept free of Swing so that it can be tested without a window.
 *
 * @author Leonard Stellbrink
 */
public class AgentSettings {

    /** How a new agent's risk perception is set. */
    public enum RiskPerception {
        /** the values typed into the panel */
        MANUAL,
        /** U(0, 2), the same r for r_sigma and r_pi (the GUI's earlier "random" option) */
        RANDOM,
        /** as in the batches: see BatchRiskPerception */
        BATCH
    }

    private final RiskPerception riskPerception;
    private final double rSigma;
    private final double rPi;
    private final double phi;
    private final double omega;
    private final boolean selective;
    private final double psi;
    private final double xi;


    /**
     * @param riskPerception
     *          how risk perception is set
     * @param rSigma
     *          r_sigma for MANUAL
     * @param rPi
     *          r_pi for MANUAL
     * @param phi
     *          the share of peers evaluated per time step
     * @param omega
     *          the share of peers selected assortatively
     * @param selective
     *          whether the agent reduces contacts selectively during an outbreak
     * @param psi
     *          the proportion of direct ties evaluated per time step
     * @param xi
     *          the proportion of ties at distance 2 evaluated per time step
     */
    public AgentSettings(RiskPerception riskPerception, double rSigma, double rPi, double phi, double omega,
            boolean selective, double psi, double xi) {
        this.riskPerception = riskPerception;
        this.rSigma = rSigma;
        this.rPi = rPi;
        this.phi = phi;
        this.omega = omega;
        this.selective = selective;
        this.psi = psi;
        this.xi = xi;
    }

    /**
     * Adds one agent with these settings, through the full Network.addAgent overload. The
     * remaining arguments are those the short overload passes (random age, age and
     * profession not considered, profession "NA", not quarantined).
     *
     * @param network
     *          the network to add the agent to
     * @param utilityFunction
     *          the agent's utility function
     * @param diseaseSpecs
     *          the disease specs
     * @return the new agent
     */
    public Agent addAgent(Network network, UtilityFunction utilityFunction, DiseaseSpecs diseaseSpecs) {
        double agentRSigma = this.rSigma;
        double agentRPi = this.rPi;
        switch (this.riskPerception) {
            case RANDOM:
                double rRandom = ThreadLocalRandom.current().nextDouble(0.0, 2.0);
                agentRSigma = rRandom;
                agentRPi = rRandom;
                break;
            case BATCH:
                double rBatch = BatchRiskPerception.draw();
                agentRSigma = rBatch;
                agentRPi = rBatch;
                break;
            case MANUAL:
            default:
                break;
        }
        return network.addAgent(utilityFunction, diseaseSpecs, agentRSigma, agentRPi, this.phi, this.omega,
                this.selective, this.psi, this.xi, AgeStructure.getInstance().getRandomAge(), false, "NA", false,
                false);
    }

    /**
     * @return how risk perception is set
     */
    public RiskPerception getRiskPerception() {
        return riskPerception;
    }

    /**
     * @return r_sigma for MANUAL
     */
    public double getRSigma() {
        return rSigma;
    }

    /**
     * @return r_pi for MANUAL
     */
    public double getRPi() {
        return rPi;
    }

    /**
     * @return the share of peers evaluated per time step
     */
    public double getPhi() {
        return phi;
    }

    /**
     * @return the share of peers selected assortatively
     */
    public double getOmega() {
        return omega;
    }

    /**
     * @return whether the agent reduces contacts selectively during an outbreak
     */
    public boolean isSelective() {
        return selective;
    }

    /**
     * @return the proportion of direct ties evaluated per time step
     */
    public double getPsi() {
        return psi;
    }

    /**
     * @return the proportion of ties at distance 2 evaluated per time step
     */
    public double getXi() {
        return xi;
    }

}
