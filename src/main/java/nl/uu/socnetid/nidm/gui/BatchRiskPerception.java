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

import org.apache.commons.math3.distribution.NormalDistribution;

/**
 * Risk perception "as in the batches", for agents added in the GUI.
 *
 * Mirrors the draw in NunnerBuskensDataGenerator.performSingleSimulation (the risk scores of
 * Nunner et al., 2023): r ~ N(1.223701, 0.4625078), redrawn until it lies in
 * [0.447402, 2.0], and the same r is used for r_sigma and r_pi. Used by the GUI only; the
 * generator keeps its own copy of these constants and is not changed by this class.
 *
 * @author Leonard Stellbrink
 */
public final class BatchRiskPerception {

    /** mean of the empirical risk scores */
    public static final double MEAN = 1.223701;
    /** standard deviation of the empirical risk scores */
    public static final double SD = 0.4625078;
    /** lower truncation bound */
    public static final double MIN = 0.447402;
    /** upper truncation bound */
    public static final double MAX = 2.0;

    private static final NormalDistribution DISTRIBUTION = new NormalDistribution(MEAN, SD);

    private BatchRiskPerception() { }

    /**
     * Draws one risk perception, used for both r_sigma and r_pi.
     *
     * @return r in [MIN, MAX]
     */
    public static double draw() {
        double r = -1.0;
        while (r > MAX || r < MIN) {
            r = DISTRIBUTION.sample();
        }
        return r;
    }

}
