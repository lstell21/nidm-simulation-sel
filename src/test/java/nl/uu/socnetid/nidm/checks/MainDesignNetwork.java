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

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ThreadLocalRandom;

import org.apache.commons.math3.distribution.NormalDistribution;

import nl.uu.socnetid.nidm.data.in.AgeStructure;
import nl.uu.socnetid.nidm.data.out.NunnerBuskensParameters;
import nl.uu.socnetid.nidm.diseases.DiseaseSpecs;
import nl.uu.socnetid.nidm.diseases.types.DiseaseType;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.system.PropertiesHandler;
import nl.uu.socnetid.nidm.utility.NunnerBuskens;
import nl.uu.socnetid.nidm.utility.UtilityFunction;

/**
 * Code checks (S10, 3 Nov 2026): a network set up exactly as one run of the batches sets it up,
 * NunnerBuskensDataGenerator.performSingleSimulation() at 490a1c7 (lines 290-466): parameters from
 * config.properties, drawn where the config marks them random; risk scores from the truncated
 * normal of Nunner et al. (2023); one agent per score with r_sigma = r_pi; an empty network
 * (iota = true). N and alpha are set by the caller, and phi = 16 / (N - 1) to six decimals, as
 * run-batch.sh --encounters 16 writes it. Only the network is built: the burn-in is the
 * caller's (Simulation.simulateUntilStable(zeta), as NunnerBuskensDataGenerator.simulatePreEpidemic()).
 *
 * @author Leonard Stellbrink
 */
final class MainDesignNetwork {

    final Network network;
    final int n;
    final double alpha;
    final double omega;
    final double d;
    final double sigma;
    final double gamma;
    final boolean selective;
    final double phi;

    private MainDesignNetwork(Network network, int n, double alpha, double omega, double d, double sigma,
            double gamma, boolean selective, double phi) {
        this.network = network;
        this.n = n;
        this.alpha = alpha;
        this.omega = omega;
        this.d = d;
        this.sigma = sigma;
        this.gamma = gamma;
        this.selective = selective;
        this.phi = phi;
    }

    /** The committed config's parameters, as the generator reads them. */
    static NunnerBuskensParameters params() {
        return PropertiesHandler.getInstance().getNunnerBuskensParameters();
    }

    /** phi as run-batch.sh --encounters 16 sets it: printf "%.6f" 16/(N-1). */
    static double phi(int n) {
        return Double.parseDouble(String.format(Locale.ROOT, "%.6f", 16.0 / (n - 1)));
    }

    /** A network of n agents with the given alpha; everything else drawn as in the batches. */
    static MainDesignNetwork build(int n, double alpha) {
        NunnerBuskensParameters p = params();
        ThreadLocalRandom r = ThreadLocalRandom.current();

        double b1 = p.isB1Random() ? r.nextDouble(p.getB1RandomMin(), p.getB1RandomMax()) : p.getB1s()[0];
        double b2 = p.isB2Random() ? r.nextDouble(p.getB2RandomMin(), p.getB2RandomMax()) : p.getB2s()[0];
        double c1 = p.isC1Random() ? r.nextDouble(p.getC1RandomMin(), p.getC1RandomMax()) : p.getC1s()[0];
        double c2 = p.isC2Random() ? r.nextDouble(p.getC2RandomMin(), p.getC2RandomMax()) : p.getC2s()[0];
        double d = p.isDRandom() ? r.nextDouble(p.getDRandomMin(), p.getDRandomMax()) : p.getDs()[0];
        double sigma = p.isSigmaRandom() ? r.nextDouble(p.getSigmaRandomMin(), p.getSigmaRandomMax()) : p.getSigmas()[0];
        double gamma = p.isGammaRandom() ? r.nextDouble(p.getGammaRandomMin(), p.getGammaRandomMax()) : p.getGammas()[0];
        int tau = p.isTauRandom() ? r.nextInt(p.getTauRandomMin(), p.getTauRandomMax()) : p.getTaus()[0];
        boolean iota = p.isIotaRandom() ? r.nextBoolean() : p.getIotas()[0];
        double psi = p.isPsiRandom() ? r.nextDouble(p.getPsiRandomMin(), p.getPsiRandomMax()) : p.getPsis()[0];
        double xi = p.isXiRandom() ? r.nextDouble(p.getXiRandomMin(), p.getXiRandomMax()) : p.getXis()[0];
        double omega = p.isOmegaRandom() ? r.nextDouble(p.getOmegaRandomMin(), p.getOmegaRandomMax()) : p.getOmegas()[0];
        boolean selective = p.isSelectiveRandom() ? r.nextBoolean() : p.getSelectives()[0];
        double phi = phi(n);

        UtilityFunction uf = new NunnerBuskens(b1, b2, alpha, c1, c2, d);
        DiseaseSpecs ds = new DiseaseSpecs(DiseaseType.SIR, tau, sigma, gamma, 0);

        // risk scores as in the generator (lines 431-449)
        List<Double> riskScores = new ArrayList<Double>(n);
        NormalDistribution nd = new NormalDistribution(1.223701, 0.4625078);
        while (riskScores.size() < n) {
            double riskScore = -1.0;
            while (riskScore > 2.0 || riskScore < 0.447402) {
                riskScore = nd.sample();
            }
            riskScores.add(riskScore);
        }
        Collections.shuffle(riskScores);

        Network network = new Network();
        // as the generator (S11): the switches from the config, off by default
        network.setFixOrder(PropertiesHandler.getInstance().isFixOrder());
        network.setFixD2(PropertiesHandler.getInstance().isFixD2());
        for (int i = 0; i < n; i++) {
            double rs = riskScores.get(i);
            network.addAgent(uf, ds, rs, rs, phi, omega, selective, psi, xi,
                    AgeStructure.getInstance().getRandomAge(), false, "NA", false, false);
        }
        if (!iota) {
            network.createFullNetwork();
        }
        return new MainDesignNetwork(network, n, alpha, omega, d, sigma, gamma, selective, phi);
    }
}
