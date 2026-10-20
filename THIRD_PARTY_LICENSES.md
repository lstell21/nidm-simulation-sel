# Third-party licences: batch jar

This file covers `nidm-4.0.1-batch.jar` (built by `mvn package` as
`target/nidm-4.0.1-batch.jar`; see `batch/README.md`). The jar contains this
repository's own code, licensed under the GNU General Public License v3.0
(`LICENSE`, in the jar as `META-INF/LICENSE`), and the third-party code listed
below, each part under its own licence. The jar carries a copy of this file
(`META-INF/THIRD_PARTY_LICENSES.md`) and of every licence text named here
(`META-INF/licenses/`, from `licenses/` in this repository).

It does **not** cover `nidm-4.0.1.jar`, the Maven build's fat jar. That jar
bundles the complete gephi-toolkit and is not distributed as a release.

## Bundled

| Component | Version | Bundled part | Licence (as distributed here) | Licence text | Source |
|---|---|---|---|---|---|
| Apache Log4j API | 2.23.1 | whole library | Apache-2.0 | `licenses/third-party/log4j-api-2.23.1-LICENSE.txt`, NOTICE alongside | [log4j-api-2.23.1-sources.jar](https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-api/2.23.1/log4j-api-2.23.1-sources.jar) |
| Apache Log4j Core | 2.23.1 | whole library | Apache-2.0 | `licenses/third-party/log4j-core-2.23.1-LICENSE.txt`, NOTICE alongside | [log4j-core-2.23.1-sources.jar](https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.23.1/log4j-core-2.23.1-sources.jar) |
| Apache Commons Math | 2.1 | whole library | Apache-2.0, plus the notices for translated code (Minpack, LAPACK, Mersenne Twister, …) in its LICENSE and NOTICE | `licenses/third-party/commons-math-2.1-LICENSE.txt`, NOTICE alongside | [commons-math-2.1-sources.jar](https://repo1.maven.org/maven2/org/apache/commons/commons-math/2.1/commons-math-2.1-sources.jar) |
| Apache Commons Math 3 | 3.6.1 | whole library | Apache-2.0, plus the notices for translated code in its LICENSE and NOTICE | `licenses/third-party/commons-math3-3.6.1-LICENSE.txt`, NOTICE alongside | [commons-math3-3.6.1-sources.jar](https://repo1.maven.org/maven2/org/apache/commons/commons-math3/3.6.1/commons-math3-3.6.1-sources.jar) |
| GraphStream gs-core | 1.3 | whole library | LGPL-3.0 (dual-licensed LGPL-3.0 or CeCILL-C; distributed here under LGPL-3.0) | `licenses/LGPL-3.0.txt` with `LICENSE` (GPL-3.0); `licenses/CeCILL-C-V1-en.txt` for reference | [gs-core-1.3-sources.jar](https://repo1.maven.org/maven2/org/graphstream/gs-core/1.3/gs-core-1.3-sources.jar) |
| GraphStream gs-algo | 1.3 | whole library | LGPL-3.0 (as gs-core) | as gs-core | [gs-algo-1.3-sources.jar](https://repo1.maven.org/maven2/org/graphstream/gs-algo/1.3/gs-algo-1.3-sources.jar) |
| Gephi | 0.9.3 (from the gephi-toolkit 0.9.3-SNAPSHOT jar) | one interface: `org.gephi.io.processor.spi.Processor` | GPL-3.0 (dual-licensed CDDL-1.0 or GPL-3.0; distributed here under GPL-3.0) | `LICENSE`; `licenses/CDDL-1.0.txt` for reference | [Processor.java at tag v0.9.3](https://github.com/gephi/gephi/blob/v0.9.3/modules/ImportAPI/src/main/java/org/gephi/io/processor/spi/Processor.java) |

- **NOTICE files.** The four Apache components' `NOTICE` files are merged into
  `META-INF/NOTICE` in the jar and also kept verbatim under
  `META-INF/licenses/third-party/`.
- **Gephi interface.** Its source was checked against the bundled class
  (20 Oct 2026): the v0.9.3 source file, compiled for Java 8, gives the same
  members, descriptors and signatures (`javap -p -s -c`) as the class in the
  gephi-toolkit 0.9.3-SNAPSHOT jar.
- **LGPL-3.0.** GraphStream is bundled unmodified and unobfuscated. A modified
  GraphStream can replace it by putting it ahead of the jar on the classpath.

## Left out, and why

The batch jar holds only what a batch run loads. This was established with
`java -verbose:class` on batch runs: N = 80, centralities off and on. It was
then confirmed by the test runs in every batch mode (`--ep-structure` dynamic
and both, ω fixed and random, centralities off and on). Everything else the
Maven build bundles is left out, including:

- **The rest of gephi-toolkit 0.9.3-SNAPSHOT.** That is Gephi itself, NetBeans
  Platform 8.2, Apache POI/Batik/Xalan, iText 5, the MySQL/PostgreSQL/SQL Server/
  SQLite JDBC drivers, Colt and others. Gephi runs only on the GEXF path-length
  route (`NetworkStats.getAvPathLength()` with a GEXF file), which batch runs
  never take; the one interface above is loaded only by the bytecode verifier.
  Three further reasons it stays out:
  - Colt's `hep.aida.*` packages are LGPL with a ban on military use. That is a
    field-of-use restriction GPL-3.0 does not allow.
  - The licence of Colt's `corejava.Format` could not be established.
  - The exact source of the snapshot build cannot be pinned to a commit.
- **maven-model 3.6.1 and plexus-utils 3.2.0.** No code in this repository uses
  them. plexus-utils' `MXParser` is under the Indiana University Extreme! Lab
  licence, whose restrictions on use of the university's name are of the kind
  the FSF treats as GPL-incompatible.
- **Other unused dependencies.** commons-io, GraphStream gs-ui, pherd and mbox2,
  and GraphStream's optional dependencies JFreeChart, JCommon, iText 2.1.5,
  Bouncy Castle, scala-library and xml-apis.

The GUI (`UserInterface`) and the GEXF route need these libraries. Use the
Maven build for them (`batch/README.md` → "Running on another machine").
