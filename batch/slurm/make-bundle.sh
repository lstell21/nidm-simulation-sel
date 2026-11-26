#!/bin/sh
# Bundle for the final re-run batches on the AI-Lab cluster (S9, 2 Nov 2026). Made on the
# laptop; the cluster runs exactly this bundle (batch/slurm/final.sh), without git or Maven.
#
#   dist/selcor-final-<short hash>.tgz      one folder selcor-final-<short hash>/ holding
#       git archive HEAD (without data/, see below), the batch jar target/nidm-4.0.1-batch.jar
#       and BUNDLE-PROVENANCE.txt (commit, branch, dirty 0, jar SHA-256, the jar's
#       git.properties commit and build time, java -version of the build, when and where made)
#   dist/selcor-final-<short hash>.tgz.sha256
#
# Run from the root of a clean clone after "mvn package -DskipTests" at HEAD:
#   ./batch/slurm/make-bundle.sh [--allow-unpushed]
# It refuses a dirty tree (untracked files count too), a HEAD that is not on origin (the
# recorded commit must be one others can check out; --allow-unpushed for a local smoke test
# only, recorded as pushed=no), a missing batch jar, a jar whose git.properties does not name
# HEAD or says dirty, an existing bundle of the same name, and a bundle with a Git LFS pointer
# instead of a resource file (git-lfs missing).
#
# data/ is left out: about 4.3 GB of Git LFS data from the 2019-2021 projects that no batch
# run reads (the batch reads src/main/resources). Everything else is HEAD as committed, with
# the line endings stored in git (core.autocrlf off), so the cluster's sh reads LF scripts.
# Environment: MVN is not needed; JAVA_HOME (if set) names the JDK whose version is recorded.

set -u

say() { echo "[$(date '+%F %T')] $*"; }
die() { say "STOPPED: $*"; exit 1; }

UNPUSHED=""
case "${1:-}" in
    "") ;;
    --allow-unpushed) UNPUSHED=1 ;;
    *) die "unknown option: $1 (only --allow-unpushed)" ;;
esac

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git clone; cd to the clone root first"
[ "$(cd "$TOP" && pwd -P)" = "$(pwd -P)" ] || die "run this from the root of the clone ($TOP)"
[ -f batch/run-batch.sh ] && [ -f batch/slurm/final.sh ] || die "$(pwd) is not an nidm-simulation-sel clone with batch/slurm/"

# 1. clean clone at a known commit
[ -z "$(git status --porcelain)" ] || die "the clone is not clean (git status --short); untracked files count too"
HEAD=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short=7 HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
NAME="selcor-final-$SHORT"
say "clone ok: $SHORT on $BRANCH, clean"
ON_ORIGIN=$(git branch -r --contains HEAD 2>/dev/null | grep -c '^ *origin/')
if [ "$ON_ORIGIN" -gt 0 ]; then
    PUSHED=yes
elif [ -n "$UNPUSHED" ]; then
    PUSHED=no; NAME="$NAME-unpushed"
    say "HEAD is on no origin branch: bundle for a local smoke test only ($NAME)"
else
    die "HEAD $SHORT is on no origin branch (git branch -r --contains HEAD): push first (--allow-unpushed for a local smoke test)"
fi

# 2. the batch jar was built from HEAD, clean
JAR=target/nidm-4.0.1-batch.jar
[ -f "$JAR" ] || die "missing $JAR: run mvn package -DskipTests first"
command -v unzip > /dev/null 2>&1 || die "unzip is needed to read the jar's git.properties"
JAR_GIT=$(unzip -p "$JAR" git.properties | tr -d '\r')
gp() { printf '%s\n' "$JAR_GIT" | sed -n "s/^git\.$1=//p" | sed 's/\\//g'; }
[ "$(gp commit.id)" = "$HEAD" ] || die "$JAR was built from $(gp commit.id), not HEAD $HEAD: run mvn package -DskipTests"
[ "$(gp dirty)" = "false" ] || die "$JAR was built from a dirty tree (git.properties git.dirty=$(gp dirty)): commit, then mvn package -DskipTests"
JAR_SHA=$(sha256sum "$JAR" | cut -c1-64)
say "jar ok: $JAR built $(gp build.time) from $SHORT, clean; sha256 $JAR_SHA"

# 3. stage: git archive HEAD without data/, plus the jar and the provenance file
mkdir -p dist
[ ! -e "dist/$NAME.tgz" ] || die "dist/$NAME.tgz exists: keep it (it may be on the cluster already) or remove it and its .sha256 first"
STAGE=$(mktemp -d) || die "mktemp failed"
trap 'rm -rf "$STAGE"' EXIT
git -c core.autocrlf=false archive --format=tar --prefix="$NAME/" HEAD -- . ':(exclude)data' \
    | tar xf - -C "$STAGE" || die "git archive failed"
PTR=$(grep -rl '^version https://git-lfs' "$STAGE/$NAME" 2>/dev/null | head -3)
[ -z "$PTR" ] || die "Git LFS pointers instead of files (is git-lfs installed?): $PTR"
mkdir -p "$STAGE/$NAME/target" && cp "$JAR" "$STAGE/$NAME/target/" || die "cannot copy the jar"

if [ -n "${JAVA_HOME:-}" ]; then
    JH=$JAVA_HOME
    command -v cygpath > /dev/null 2>&1 && JH=$(cygpath -u "$JAVA_HOME")
    JAVA="$JH/bin/java"
else
    JAVA=java
fi
JV=$("$JAVA" -version 2>&1 | tr -d '\r')
{
    echo "# Written by batch/slurm/make-bundle.sh. run-batch.sh and final.sh read the git lines"
    echo "# from here when there is no .git (the cluster's compute nodes need no git)."
    echo "bundle=$NAME"
    echo "commit=$HEAD"
    echo "branch=$BRANCH"
    echo "dirty=0"
    echo "pushed=$PUSHED"
    echo "jar=$JAR"
    echo "jar.sha256=$JAR_SHA"
    echo "jar.git.commit.id=$(gp commit.id)"
    echo "jar.git.dirty=$(gp dirty)"
    echo "jar.build.time=$(gp build.time)"
    echo "build.java=$(printf '%s\n' "$JV" | sed -n 1p)"
    echo "build.java.runtime=$(printf '%s\n' "$JV" | sed -n 2p)"
    echo "made=$(date -Iseconds)"
    echo "made.on=$(hostname) ($(uname -s))"
    echo "excluded=data/ (Git LFS data of the 2019-2021 projects; no batch reads it)"
} > "$STAGE/$NAME/BUNDLE-PROVENANCE.txt"

# 4. pack and check
tar czf "dist/$NAME.tgz" -C "$STAGE" "$NAME" || die "tar failed"
(cd dist && sha256sum "$NAME.tgz" > "$NAME.tgz.sha256" && sha256sum -c --status "$NAME.tgz.sha256") \
    || die "sha256 failed"
FILES=$(tar tzf "dist/$NAME.tgz" | grep -vc '/$')
say "bundle: dist/$NAME.tgz  $(wc -c < "dist/$NAME.tgz") bytes, $FILES files"
say "sha256: $(cut -c1-64 "dist/$NAME.tgz.sha256")"
say "provenance:"
sed -n '/^[^#]/s/^/    /p' "$STAGE/$NAME/BUNDLE-PROVENANCE.txt"
