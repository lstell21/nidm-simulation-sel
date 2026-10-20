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
package nl.uu.socnetid.nidm.io.csv;

import java.io.IOException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import nl.uu.socnetid.nidm.agents.Agent;
import nl.uu.socnetid.nidm.data.out.DataGeneratorData;
import nl.uu.socnetid.nidm.data.out.NunnerBuskensParameters;
import nl.uu.socnetid.nidm.networks.Network;

/**
 * Tie-level output for the mechanism analysis (export.tie.events=true): writes
 * tie-events.csv (one row per tie formed or dissolved while an infection is active) and
 * transmissions.csv (one row per infection through computeDiseaseTransmission; the index
 * case has none).
 *
 * The log only observes. It never uses the model's random streams (ThreadLocalRandom,
 * Collections.shuffle) and never calls Network.hasActiveInfection(), which writes a network
 * attribute. The model decides an infection with a single draw against P(infection | nI)
 * and identifies no infector; the log attributes one of the nI infected neighbours
 * uniformly at random, drawn from its own java.util.Random.
 *
 * sim.round is the cumulative round counter that round-summary.csv writes: during a round,
 * SimulationStats holds the previous round's value, so events are labelled rounds + 1.
 *
 * Rows are buffered and flushed once per simulation (CsvFileWriter.writeLine flushes every
 * line, which would cost a flush per tie event).
 *
 * @author Leonard Stellbrink
 */
public class TieEventLog {

    private static final Logger logger = LogManager.getLogger(TieEventLog.class);

    private final DataGeneratorData<NunnerBuskensParameters> dgData;
    private final EventWriter tieEventsWriter;
    private final EventWriter transmissionsWriter;
    // infector attribution only; separate from the model's random streams
    private final Random attributionRandom = new Random();
    // round in which a tie was formed while an infection was active, keyed by agent pair;
    // ties absent from the map existed before the outbreak (-1)
    private final Map<String, Integer> tieFormedRound = new HashMap<String, Integer>();
    private Network network;


    /**
     * Creates the log and both CSV files in the given export path.
     *
     * @param exportPath
     *          the directory the CSV files are written to (with trailing separator)
     * @param dgData
     *          the data generator data (simulation ids, rounds, parameters)
     * @throws IOException
     *          if a file cannot be created
     */
    public TieEventLog(String exportPath, DataGeneratorData<NunnerBuskensParameters> dgData) throws IOException {
        this.dgData = dgData;
        this.tieEventsWriter = new TieEventsWriter(exportPath + "tie-events.csv", dgData);
        this.transmissionsWriter = new TransmissionsWriter(exportPath + "transmissions.csv", dgData);
    }

    /**
     * Attaches the log to a newly created network and forgets the previous network's ties.
     *
     * @param network
     *          the network of the simulation about to start
     */
    public void attach(Network network) {
        this.network = network;
        this.tieFormedRound.clear();
        network.setTieEventLog(this);
    }

    /**
     * Called by Agent.connectTo after a requested tie was accepted and created.
     *
     * @param initiator
     *          the agent that requested the tie
     * @param partner
     *          the agent that accepted it
     */
    public void tieFormed(Agent initiator, Agent partner) {
        if (!activeInfection()) {
            this.tieFormedRound.remove(key(initiator, partner));
            return;
        }
        int round = currentRound();
        this.tieFormedRound.put(key(initiator, partner), round);
        // adding the tie i-j leaves N(i) and N(j) without i and j, so the common
        // neighbours after the change equal those before it
        // distance.after is defined for dissolutions only: NA
        appendTieEvent(round, "form", initiator, partner, commonNeighbours(initiator, partner), null, round);
    }

    /**
     * Called by Agent.disconnectFrom after the tie was removed.
     *
     * @param initiator
     *          the agent that dissolved the tie
     * @param partner
     *          the agent on the other side
     */
    public void tieDissolved(Agent initiator, Agent partner) {
        Integer formed = this.tieFormedRound.remove(key(initiator, partner));
        if (!activeInfection()) {
            return;
        }
        // as for formation, removing i-j does not change the common neighbours
        appendTieEvent(currentRound(), "dissolve", initiator, partner, commonNeighbours(initiator, partner),
                distance(initiator, partner), formed == null ? -1 : formed);
    }

    /**
     * Called by Agent.computeDiseaseTransmission after the agent was infected.
     *
     * @param infectee
     *          the newly infected agent
     * @param nI
     *          the number of infected neighbours the infection probability was computed with
     */
    public void transmission(Agent infectee, int nI) {
        List<Agent> infectedNeighbours = new ArrayList<Agent>();
        for (Agent neighbour : infectee.getConnections()) {
            if (neighbour.isInfected()) {
                infectedNeighbours.add(neighbour);
            }
        }
        if (infectedNeighbours.size() != nI) {
            logger.warn("Infected neighbours of " + infectee.getId() + ": " + infectedNeighbours.size()
                    + ", but nI = " + nI);
        }
        Agent infector = infectedNeighbours.isEmpty() ? null :
            infectedNeighbours.get(this.attributionRandom.nextInt(infectedNeighbours.size()));
        Integer formed = infector == null ? null : this.tieFormedRound.get(key(infectee, infector));
        try {
            this.transmissionsWriter.appendRow(
                    this.dgData.getSimStats().getUid(),
                    String.valueOf(this.dgData.getSimStats().getSimPerUpc()),
                    String.valueOf(currentRound()),
                    infectee.getId(),
                    infector == null ? null : infector.getId(),
                    String.valueOf(infectee.getRSigma()),
                    infector == null ? null : String.valueOf(infector.getRSigma()),
                    String.valueOf(formed == null ? -1 : formed),
                    String.valueOf(nI));
        } catch (IOException e) {
            logger.error(e);
        }
    }

    /**
     * Flushes both files; called once per simulation.
     */
    public void flush() {
        try {
            this.tieEventsWriter.flush();
            this.transmissionsWriter.flush();
        } catch (IOException e) {
            logger.error(e);
        }
    }

    /**
     * Flushes and closes both files.
     */
    public void close() {
        try {
            this.tieEventsWriter.flush();
            this.tieEventsWriter.close();
            this.transmissionsWriter.flush();
            this.transmissionsWriter.close();
        } catch (IOException e) {
            logger.error(e);
        }
    }


    private void appendTieEvent(int round, String event, Agent initiator, Agent partner, int common,
            Integer distanceAfter, int formedRound) {
        try {
            this.tieEventsWriter.appendRow(
                    this.dgData.getSimStats().getUid(),
                    String.valueOf(this.dgData.getSimStats().getSimPerUpc()),
                    String.valueOf(round),
                    event,
                    initiator.getId(),
                    partner.getId(),
                    diseaseState(initiator),
                    diseaseState(partner),
                    String.valueOf(initiator.getRSigma()),
                    String.valueOf(partner.getRSigma()),
                    String.valueOf(this.dgData.getUtilityModelParams().isCurrSelective()),
                    String.valueOf(common),
                    distanceAfter == null ? null : String.valueOf(distanceAfter),
                    String.valueOf(formedRound));
        } catch (IOException e) {
            logger.error(e);
        }
    }

    // the round being computed, as round-summary.csv will label it
    private int currentRound() {
        return this.dgData.getSimStats().getRounds() + 1;
    }

    // same test as Network.hasActiveInfection(), without its attribute write
    private boolean activeInfection() {
        Iterator<Agent> it = this.network.getAgentIterator();
        while (it.hasNext()) {
            if (it.next().isInfected()) {
                return true;
            }
        }
        return false;
    }

    private static String key(Agent a, Agent b) {
        String idA = a.getId();
        String idB = b.getId();
        return idA.compareTo(idB) < 0 ? idA + "|" + idB : idB + "|" + idA;
    }

    private static int commonNeighbours(Agent a, Agent b) {
        Set<Agent> neighboursA = new HashSet<Agent>(a.getConnections());
        int common = 0;
        for (Agent neighbour : b.getConnections()) {
            if (neighboursA.contains(neighbour)) {
                common++;
            }
        }
        return common;
    }

    // breadth-first search over the current ties; -1 if b is unreachable from a
    private static int distance(Agent a, Agent b) {
        Set<Agent> visited = new HashSet<Agent>();
        Deque<Agent> frontier = new ArrayDeque<Agent>();
        visited.add(a);
        frontier.add(a);
        int dist = 0;
        while (!frontier.isEmpty()) {
            dist++;
            for (int i = frontier.size(); i > 0; i--) {
                for (Agent neighbour : frontier.poll().getConnections()) {
                    if (neighbour == b) {
                        return dist;
                    }
                    if (visited.add(neighbour)) {
                        frontier.add(neighbour);
                    }
                }
            }
        }
        return -1;
    }

    private static String diseaseState(Agent agent) {
        switch (agent.getDiseaseGroup()) {
            case SUSCEPTIBLE:
                return "S";
            case INFECTED:
                return "I";
            case RECOVERED:
                return "R";
            case VACCINATED:
                return "V";
            default:
                return null;
        }
    }


    /**
     * CSV file in the format of the other writers (';', NA for missing values), but rows are
     * appended without a flush per line. CsvFileWriter's constructor writes the header via
     * initCols() before subclass fields are set, so each file's columns are a constant.
     */
    private abstract static class EventWriter extends CsvFileWriter<NunnerBuskensParameters> {

        EventWriter(String fileName, DataGeneratorData<NunnerBuskensParameters> dgData) throws IOException {
            super(fileName, dgData);
        }

        protected abstract List<String> columns();

        @Override
        protected void initCols() {
            writeLine(columns());
        }

        @Override
        public void writeCurrentData() {
            // rows are written by TieEventLog
        }

        void appendRow(String... values) throws IOException {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < values.length; i++) {
                if (i > 0) {
                    sb.append(';');
                }
                sb.append(values[i] == null ? "NA" : values[i]);
            }
            sb.append('\n');
            append(sb);
        }
    }

    private static class TieEventsWriter extends EventWriter {

        private static final List<String> COLS = Arrays.asList(
                "sim.uid", "sim.cnt", "sim.round", "event",
                "initiator.id", "partner.id",
                "initiator.disease.state", "partner.disease.state",
                "initiator.r.sigma", "partner.r.sigma",
                "nb.selective", "common.neighbours", "distance.after", "tie.formed.round");

        TieEventsWriter(String fileName, DataGeneratorData<NunnerBuskensParameters> dgData) throws IOException {
            super(fileName, dgData);
        }

        @Override
        protected List<String> columns() {
            return COLS;
        }
    }

    private static class TransmissionsWriter extends EventWriter {

        private static final List<String> COLS = Arrays.asList(
                "sim.uid", "sim.cnt", "sim.round",
                "infectee.id", "infector.id",
                "infectee.r.sigma", "infector.r.sigma",
                "tie.formed.round", "infectee.infected.neighbours");

        TransmissionsWriter(String fileName, DataGeneratorData<NunnerBuskensParameters> dgData) throws IOException {
            super(fileName, dgData);
        }

        @Override
        protected List<String> columns() {
            return COLS;
        }
    }

}
