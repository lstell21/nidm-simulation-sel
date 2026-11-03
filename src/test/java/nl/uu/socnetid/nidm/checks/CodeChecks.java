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

import java.io.File;
import java.io.IOException;
import java.io.PrintWriter;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ThreadLocalRandom;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.networks.Network;
import nl.uu.socnetid.nidm.simulation.Simulation;
import nl.uu.socnetid.nidm.simulation.SimulationListener;

/**
 * Code checks (S10, 3 Nov 2026): a harness, not part of any batch and not run by mvn test. It
 * builds networks as the batches do (MainDesignNetwork), runs the burn-in with the model's own
 * Simulation and measures; nothing in src/main is changed or bypassed.
 *
 * <pre>
 * java -cp "target/test-classes;target/classes;target/nidm-4.0.1.jar" nl.uu.socnetid.nidm.checks.CodeChecks MODE ...
 *   order   OUTDIR TAG [RUNS]            item 2: processing order of Simulation.computeAgentDynamics()
 *                                        in the 10 burn-in rounds of RUNS runs at N = 80 (default 2)
 *   order-compare FILE1 FILE2            item 2: the orders of two such JVMs, run by run
 *   burnin  OUTDIR N ALPHA NETWORKS [T]  items 1 and 3: NETWORKS networks burned in for zeta steps,
 *                                        checked, then run on to step T (default 30) and checked again
 * </pre>
 * (":" instead of ";" on Linux.) Output: CSV files in OUTDIR and a summary on stdout.
 *
 * @author Leonard Stellbrink
 */
public final class CodeChecks {

    private CodeChecks() { }

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            throw new IllegalArgumentException("mode: order | order-compare | burnin");
        }
        if ("order".equals(args[0])) {
            order(new File(args[1]), args[2], args.length > 3 ? Integer.parseInt(args[3]) : 2);
        } else if ("order-compare".equals(args[0])) {
            orderCompare(new File(args[1]), new File(args[2]));
        } else if ("burnin".equals(args[0])) {
            burnin(new File(args[1]), Integer.parseInt(args[2]), Double.parseDouble(args[3]),
                    Integer.parseInt(args[4]), args.length > 5 ? Integer.parseInt(args[5]) : 30);
        } else {
            throw new IllegalArgumentException("unknown mode " + args[0]);
        }
    }

    // ------------------------------------------------------------------ item 2: agent order

    /** Records the order in which computeAgentDynamics() hands agents to computeAgentRound. */
    static final class RecordingSimulation extends Simulation {
        final List<List<String>> rounds = new ArrayList<List<String>>();
        private List<String> current = new ArrayList<String>();

        RecordingSimulation(Network network) {
            super(network, false);
            addSimulationListener(new SimulationListener() {
                @Override public void notifySimulationStarted(Simulation simulation) { }
                @Override public void notifyRoundFinished(Simulation simulation) {
                    rounds.add(current);
                    current = new ArrayList<String>();
                }
                @Override public void notifyInfectionDefeated(Simulation simulation) { }
                @Override public void notifySimulationFinished(Simulation simulation) { }
            });
        }

        @Override
        protected void computeAgentRound(Agent agent, int delay) {
            this.current.add(agent.getId());
            super.computeAgentRound(agent, delay);
        }
    }

    private static void order(File outDir, String tag, int runs) throws IOException {
        outDir.mkdirs();
        int n = 80;
        int zeta = MainDesignNetwork.params().getZeta();
        List<List<List<String>>> allRuns = new ArrayList<List<List<String>>>();
        List<List<String>> hashOrders = new ArrayList<List<String>>();
        try (PrintWriter out = writer(new File(outDir, "order-" + tag + ".csv"));
             PrintWriter hash = writer(new File(outDir, "hash-order-" + tag + ".csv"))) {
            out.println("jvm;run;alpha;round;position;agent.id");
            hash.println("jvm;run;position;agent.id;identity.hash");
            for (int run = 1; run <= runs; run++) {
                // main design: alpha ~ U[0, 0.9]
                double alpha = ThreadLocalRandom.current().nextDouble(0.0, 0.9);
                MainDesignNetwork md = MainDesignNetwork.build(n, alpha);
                // a HashSet of the agents, as computeAgentDynamics builds agentsAll (Simulation.java:363)
                List<String> hashOrder = new ArrayList<String>();
                for (Agent agent : new HashSet<Agent>(new ArrayList<Agent>(md.network.getAgents()))) {
                    hashOrder.add(agent.getId());
                    hash.println(tag + ";" + run + ";" + hashOrder.size() + ";" + agent.getId() + ";"
                            + System.identityHashCode(agent));
                }
                hashOrders.add(hashOrder);
                RecordingSimulation simulation = new RecordingSimulation(md.network);
                simulation.simulateUntilStable(zeta);
                allRuns.add(simulation.rounds);
                for (int r = 0; r < simulation.rounds.size(); r++) {
                    List<String> o = simulation.rounds.get(r);
                    for (int p = 0; p < o.size(); p++) {
                        out.println(tag + ";" + run + ";" + fmt(alpha) + ";" + (r + 1) + ";" + (p + 1) + ";" + o.get(p));
                    }
                }
            }
        }

        System.out.println("item 2, JVM " + tag + ": processing order in computeAgentDynamics(), N = " + n
                + ", " + zeta + " burn-in rounds per run");
        for (int run = 0; run < allRuns.size(); run++) {
            List<List<String>> rounds = allRuns.get(run);
            StringBuilder firsts = new StringBuilder();
            Set<String> distinctFirsts = new HashSet<String>();
            int firstIsHashFirst = 0;
            for (List<String> o : rounds) {
                firsts.append(o.get(0)).append(' ');
                distinctFirsts.add(o.get(0));
                if (o.get(0).equals(hashOrders.get(run).get(0))) {
                    firstIsHashFirst++;
                }
            }
            System.out.println("  run " + (run + 1) + ": agents per round " + rounds.get(0).size()
                    + "; first agent per round: " + firsts + "(" + distinctFirsts.size() + " distinct; "
                    + firstIsHashFirst + " of " + rounds.size() + " rounds = first of a HashSet of the agents)");
            double tauSum = 0, idSum = 0, tauMin = 1, idMin = 1;
            for (int r = 1; r < rounds.size(); r++) {
                double tau = kendallTau(rounds.get(r - 1), rounds.get(r));
                double id = identicalPositions(rounds.get(r - 1), rounds.get(r));
                tauSum += tau; idSum += id; tauMin = Math.min(tauMin, tau); idMin = Math.min(idMin, id);
            }
            int pairs = rounds.size() - 1;
            System.out.println(String.format(Locale.ROOT,
                    "    consecutive rounds (%d pairs): Kendall tau mean %.3f (min %.3f), identical positions mean %.3f (min %.3f)",
                    pairs, tauSum / pairs, tauMin, idSum / pairs, idMin));
            System.out.println(String.format(Locale.ROOT,
                    "    round 1 vs round %d: Kendall tau %.3f, identical positions %.3f; round 1 vs HashSet order: tau %.3f",
                    rounds.size(), kendallTau(rounds.get(0), rounds.get(rounds.size() - 1)),
                    identicalPositions(rounds.get(0), rounds.get(rounds.size() - 1)),
                    kendallTau(rounds.get(0), hashOrders.get(run))));
        }
        for (int run = 1; run < allRuns.size(); run++) {
            compareRuns("  run 1 vs run " + (run + 1) + " (same JVM, by agent id)", allRuns.get(0), allRuns.get(run),
                    hashOrders.get(0), hashOrders.get(run));
        }
    }

    private static void compareRuns(String label, List<List<String>> a, List<List<String>> b,
            List<String> hashA, List<String> hashB) {
        int rounds = Math.min(a.size(), b.size());
        double tauSum = 0, idSum = 0;
        int sameFirst = 0;
        for (int r = 0; r < rounds; r++) {
            tauSum += kendallTau(a.get(r), b.get(r));
            idSum += identicalPositions(a.get(r), b.get(r));
            if (a.get(r).get(0).equals(b.get(r).get(0))) {
                sameFirst++;
            }
        }
        System.out.println(String.format(Locale.ROOT,
                "%s: round by round Kendall tau mean %.3f, identical positions mean %.3f, same first agent in %d of %d rounds;"
                + " HashSet orders: tau %.3f, identical positions %.3f",
                label, tauSum / rounds, idSum / rounds, sameFirst, rounds,
                kendallTau(hashA, hashB), identicalPositions(hashA, hashB)));
    }

    private static void orderCompare(File f1, File f2) throws IOException {
        Map<Integer, List<List<String>>> a = readOrders(f1);
        Map<Integer, List<List<String>>> b = readOrders(f2);
        Map<Integer, List<String>> ha = readHashOrders(new File(f1.getParentFile(), f1.getName().replace("order-", "hash-order-")));
        Map<Integer, List<String>> hb = readHashOrders(new File(f2.getParentFile(), f2.getName().replace("order-", "hash-order-")));
        for (Integer run : a.keySet()) {
            if (b.containsKey(run)) {
                compareRuns("  run " + run + ": " + f1.getName() + " vs " + f2.getName() + " (separate JVMs, by agent id)",
                        a.get(run), b.get(run), ha.get(run), hb.get(run));
            }
        }
    }

    private static Map<Integer, List<List<String>>> readOrders(File f) throws IOException {
        Map<Integer, List<List<String>>> runs = new HashMap<Integer, List<List<String>>>();
        List<String> lines = Files.readAllLines(f.toPath(), StandardCharsets.UTF_8);
        for (String line : lines.subList(1, lines.size())) {
            String[] c = line.split(";");
            int run = Integer.parseInt(c[1]);
            int round = Integer.parseInt(c[3]);
            if (!runs.containsKey(run)) {
                runs.put(run, new ArrayList<List<String>>());
            }
            List<List<String>> rounds = runs.get(run);
            while (rounds.size() < round) {
                rounds.add(new ArrayList<String>());
            }
            rounds.get(round - 1).add(c[5]);
        }
        return runs;
    }

    private static Map<Integer, List<String>> readHashOrders(File f) throws IOException {
        Map<Integer, List<String>> runs = new HashMap<Integer, List<String>>();
        List<String> lines = Files.readAllLines(f.toPath(), StandardCharsets.UTF_8);
        for (String line : lines.subList(1, lines.size())) {
            String[] c = line.split(";");
            int run = Integer.parseInt(c[1]);
            if (!runs.containsKey(run)) {
                runs.put(run, new ArrayList<String>());
            }
            runs.get(run).add(c[3]);
        }
        return runs;
    }

    /** Kendall's tau between two orders of the same items (no ties): 1 identical, -1 reversed. */
    static double kendallTau(List<String> a, List<String> b) {
        Map<String, Integer> posB = new HashMap<String, Integer>();
        for (int i = 0; i < b.size(); i++) {
            posB.put(b.get(i), i);
        }
        long concordant = 0, discordant = 0;
        for (int i = 0; i < a.size(); i++) {
            for (int j = i + 1; j < a.size(); j++) {
                if (posB.get(a.get(i)) < posB.get(a.get(j))) {
                    concordant++;
                } else {
                    discordant++;
                }
            }
        }
        return (concordant - discordant) / (double) (concordant + discordant);
    }

    /** Share of positions holding the same item in both orders. */
    static double identicalPositions(List<String> a, List<String> b) {
        int same = 0;
        for (int i = 0; i < a.size(); i++) {
            if (a.get(i).equals(b.get(i))) {
                same++;
            }
        }
        return same / (double) a.size();
    }

    // --------------------------------------------------- items 1 and 3: burned-in networks

    /** Mean degree and clustering after every round, as the round summaries compute them. */
    static final class RoundRecorder implements SimulationListener {
        final List<double[]> rows = new ArrayList<double[]>();
        private final Network network;

        RoundRecorder(Network network) {
            this.network = network;
        }

        @Override public void notifySimulationStarted(Simulation simulation) { }
        @Override public void notifyRoundFinished(Simulation simulation) {
            this.rows.add(new double[] { this.network.getAvDegree(), this.network.getAvClustering() });
        }
        @Override public void notifyInfectionDefeated(Simulation simulation) { }
        @Override public void notifySimulationFinished(Simulation simulation) { }
    }

    /** Pairwise stability over all pairs, with the model's own decision methods. */
    static final class StabilityCount {
        long pairs, ties, cutEither, cutFirst, cutBoth, addBoth, addOneSided;
        int agentsInViolation;
        boolean modelStable;
        long ms;

        String csv() {
            return pairs + ";" + ties + ";" + cutEither + ";" + cutFirst + ";" + cutBoth + ";" + addBoth + ";"
                    + addOneSided + ";" + agentsInViolation + ";" + modelStable + ";" + ms;
        }

        static String header(String suffix) {
            String[] cols = { "pairs", "ties", "viol.cut.either", "viol.cut.first", "cut.both", "viol.add.both",
                    "add.one.sided", "agents.in.violation", "model.stable", "ms.check" };
            StringBuilder sb = new StringBuilder();
            for (String c : cols) {
                sb.append(sb.length() > 0 ? ";" : "").append(c).append(suffix);
            }
            return sb.toString();
        }
    }

    /**
     * The model's own check once (Network.computeStability(), private, called by reflection: its
     * counter is reset first, so it ends at 1 if no pair violates stability, else at 0), then all
     * N (N - 1) / 2 pairs counted. computeStability() stops at the first violation and, for an
     * existing tie, asks only the agent that comes first in the agent iterator whether it wants to
     * cut (Network.java:1879-1880); "cut.first" counts that, "cut.either" either agent.
     */
    static StabilityCount stability(Network network) throws Exception {
        long t0 = System.nanoTime();
        StabilityCount s = new StabilityCount();
        Method computeStability = Network.class.getDeclaredMethod("computeStability");
        computeStability.setAccessible(true);
        network.resetTimestepsStable();
        computeStability.invoke(network);
        s.modelStable = network.getTimestepsStable() == 1;

        List<Agent> agents = new ArrayList<Agent>();
        java.util.Iterator<Agent> it = network.getAgentIterator();
        while (it.hasNext()) {
            agents.add(it.next());
        }
        Set<Agent> inViolation = new HashSet<Agent>();
        for (int i = 0; i < agents.size(); i++) {
            Agent ai = agents.get(i);
            for (int j = i + 1; j < agents.size(); j++) {
                Agent aj = agents.get(j);
                s.pairs++;
                if (ai.isDirectlyConnectedTo(aj)) {
                    s.ties++;
                    boolean ci = ai.existingConnectionTooCostly(aj);
                    boolean cj = aj.existingConnectionTooCostly(ai);
                    if (ci || cj) {
                        s.cutEither++;
                        inViolation.add(ai);
                        inViolation.add(aj);
                    }
                    if (ci) {
                        s.cutFirst++;
                    }
                    if (ci && cj) {
                        s.cutBoth++;
                    }
                } else {
                    boolean vi = ai.newConnectionValuable(aj);
                    boolean vj = aj.newConnectionValuable(ai);
                    if (vi && vj) {
                        s.addBoth++;
                        inViolation.add(ai);
                        inViolation.add(aj);
                    } else if (vi || vj) {
                        s.addOneSided++;
                    }
                }
            }
        }
        s.agentsInViolation = inViolation.size();
        s.ms = (System.nanoTime() - t0) / 1000000;
        return s;
    }

    /** Item 1: how often each second-degree neighbour is listed, over all agents of a network. */
    static String dist2(Network network) {
        long agentsWith = 0, distinct = 0, entries = 0, distinctMulti = 0, entriesMulti = 0, agents2 = 0;
        double ratioSum = 0, ratioSum2 = 0;
        int maxMult = 0;
        java.util.Iterator<Agent> it = network.getAgentIterator();
        while (it.hasNext()) {
            Agent agent = it.next();
            Map<Agent, Integer> mult = new HashMap<Agent, Integer>();
            for (Agent other : agent.getConnectionsAtDistance2()) {
                Integer m = mult.get(other);
                mult.put(other, m == null ? 1 : m + 1);
            }
            if (mult.isEmpty()) {
                continue;
            }
            agentsWith++;
            int min = Integer.MAX_VALUE, max = 0;
            for (int m : mult.values()) {
                distinct++;
                entries += m;
                if (m > 1) {
                    distinctMulti++;
                    entriesMulti += m;
                }
                min = Math.min(min, m);
                max = Math.max(max, m);
            }
            maxMult = Math.max(maxMult, max);
            ratioSum += max / (double) min;
            if (mult.size() >= 2) {
                agents2++;
                ratioSum2 += max / (double) min;
            }
        }
        return agentsWith + ";" + distinct + ";" + entries + ";" + fmt(distinctMulti / (double) distinct) + ";"
                + fmt(entriesMulti / (double) entries) + ";" + fmt(ratioSum / agentsWith) + ";"
                + fmt(agents2 == 0 ? Double.NaN : ratioSum2 / agents2) + ";" + maxMult;
    }

    private static void burnin(File outDir, int n, double alpha, int networks, int extendTo) throws Exception {
        outDir.mkdirs();
        int zeta = MainDesignNetwork.params().getZeta();
        String cell = "n" + n + "-a" + fmt(alpha);
        long tStart = System.nanoTime();
        try (PrintWriter rounds = writer(new File(outDir, "rounds-" + cell + ".csv"));
             PrintWriter stab = writer(new File(outDir, "stability-" + cell + ".csv"));
             PrintWriter d2 = writer(new File(outDir, "dist2-" + cell + ".csv"))) {
            rounds.println("N;alpha;network;round;degree.av;clustering.av");
            stab.println("N;alpha;network;omega;d;sigma;selective;phi;burnin.rounds;isStable.after.burnin;"
                    + StabilityCount.header(".10") + ";" + StabilityCount.header("." + extendTo) + ";ms.burnin;ms.extend");
            d2.println("N;alpha;network;agents.with.dist2;dist2.distinct;dist2.entries;share.distinct.mult.gt1;"
                    + "share.entries.mult.gt1;mean.ratio.max.min;mean.ratio.max.min.agents.2plus;max.mult");
            for (int k = 1; k <= networks; k++) {
                MainDesignNetwork md = MainDesignNetwork.build(n, alpha);
                RoundRecorder recorder = new RoundRecorder(md.network);

                // the burn-in, as NunnerBuskensDataGenerator.simulatePreEpidemic()
                long t0 = System.nanoTime();
                Simulation simulation = new Simulation(md.network, false);
                simulation.addSimulationListener(recorder);
                simulation.simulateUntilStable(zeta);
                long msBurnin = (System.nanoTime() - t0) / 1000000;
                int burninRounds = simulation.getRounds() - 1;
                boolean isStable = md.network.isStable();

                StabilityCount s10 = stability(md.network);
                d2.println(n + ";" + fmt(alpha) + ";" + k + ";" + dist2(md.network));

                // on to step extendTo (a fresh Simulation, as the generator starts every stage)
                long t1 = System.nanoTime();
                Simulation more = new Simulation(md.network, false);
                more.addSimulationListener(recorder);
                more.simulateUntilStable(extendTo - zeta);
                long msExtend = (System.nanoTime() - t1) / 1000000;
                StabilityCount sT = stability(md.network);

                for (int r = 0; r < recorder.rows.size(); r++) {
                    rounds.println(n + ";" + fmt(alpha) + ";" + k + ";" + (r + 1) + ";"
                            + fmt(recorder.rows.get(r)[0]) + ";" + fmt(recorder.rows.get(r)[1]));
                }
                stab.println(n + ";" + fmt(alpha) + ";" + k + ";" + fmt(md.omega) + ";" + fmt(md.d) + ";"
                        + fmt(md.sigma) + ";" + md.selective + ";" + fmt(md.phi) + ";" + burninRounds + ";" + isStable + ";"
                        + s10.csv() + ";" + sT.csv() + ";" + msBurnin + ";" + msExtend);
                stab.flush();
                rounds.flush();
                d2.flush();
                System.out.println(String.format(Locale.ROOT,
                        "%s network %d: burn-in %d rounds (%d ms), isStable %b; after %d: model stable %b, "
                        + "%d ties, cut violations %d (first agent only %d), add violations %d (%d ms); "
                        + "after %d: model stable %b, cut %d, add %d",
                        cell, k, burninRounds, msBurnin, isStable, zeta, s10.modelStable, s10.ties, s10.cutEither,
                        s10.cutFirst, s10.addBoth, s10.ms, extendTo, sT.modelStable, sT.cutEither, sT.addBoth));
            }
        }
        System.out.println(cell + ": done in " + (System.nanoTime() - tStart) / 1000000000 + " s");
    }

    private static PrintWriter writer(File f) throws IOException {
        return new PrintWriter(Files.newBufferedWriter(f.toPath(), StandardCharsets.UTF_8));
    }

    private static String fmt(double v) {
        return String.format(Locale.ROOT, "%.6f", v);
    }
}
