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
package nl.uu.socnetid.nidm.utility;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import nl.uu.socnetid.nidm.agents.Agent;

/**
 * Shadow check of the infected agents' disease cost (check.infected.cost=true). On rerun-fixes an
 * infected agent's disease cost is sigma (manuscript Eq. 5); before, it was d * sigma. Every
 * comparison of overall utilities that decides a tie for an infected agent is evaluated a second
 * time with the old cost, and the check counts the comparisons and those whose outcome differs
 * (simulation summary: check.infected.cost.n, check.infected.cost.diff). A differing comparison
 * is logged with both utilities and both outcomes.
 *
 * The check only observes: it reuses the two utilities the decision was taken on, never changes
 * the decision, and draws no random numbers.
 *
 * @author Leonard Stellbrink
 */
public class InfectedCostCheck {

    private static final Logger logger = LogManager.getLogger(InfectedCostCheck.class);

    // comparisons evaluated a second time, and those whose outcome differs with the old cost
    private long n = 0;
    private long diff = 0;


    /**
     * Forgets the counts of the previous simulation.
     */
    public synchronized void reset() {
        this.n = 0;
        this.diff = 0;
    }

    /**
     * Evaluates a comparison of overall utilities a second time with the old disease cost and
     * counts it.
     *
     * @param decision
     *          the decision the comparison takes (for the log)
     * @param agent
     *          the infected agent whose utilities are compared
     * @param other
     *          the agent on the other side of the tie (for the log)
     * @param left
     *          the utility on the left-hand side of the comparison
     * @param right
     *          the utility on the right-hand side of the comparison
     * @param strict
     *          true for left &gt; right, false for left &gt;= right
     * @param outcome
     *          the outcome of the comparison with the current disease cost
     */
    public synchronized void compare(String decision, Agent agent, Agent other, Utility left, Utility right,
            boolean strict, boolean outcome) {
        UtilityFunction uf = agent.getUtilityFunction();
        double leftOld = uf.getOverallUtilityOldInfectedCosts(left, agent);
        double rightOld = uf.getOverallUtilityOldInfectedCosts(right, agent);
        boolean outcomeOld = strict ? leftOld > rightOld : leftOld >= rightOld;

        this.n++;
        if (outcomeOld != outcome) {
            this.diff++;
            logger.warn("check.infected.cost: " + decision + ", agent " + agent.getId() + ", other " + other.getId()
                    + (strict ? ", left > right" : ", left >= right")
                    + "; sigma: " + left.getOverallUtility() + " vs " + right.getOverallUtility() + " -> " + outcome
                    + "; d * sigma: " + leftOld + " vs " + rightOld + " -> " + outcomeOld);
        }
    }

    /**
     * @return the number of comparisons evaluated a second time
     */
    public synchronized long getN() {
        return this.n;
    }

    /**
     * @return the number of comparisons whose outcome differs with the old disease cost
     */
    public synchronized long getDiff() {
        return this.diff;
    }

}
