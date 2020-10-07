# ~\~ language=Bash filename=test/run.sh
# ~\~ begin <<lit/index.md|test/run.sh>>[0]
# taste environment
# ~\~ begin <<lit/index.md|get-script-dir>>[0]
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# ~\~ end
# ~\~ begin <<lit/index.md|define-exit-code>>[0]
EXIT_CODE=0
# ~\~ end

# function definitions
# ~\~ begin <<lit/index.md|reporting>>[0]
function report-success() {
    echo -e "\033[32m✓\033[m  $1"
}
# ~\~ end
# ~\~ begin <<lit/index.md|reporting>>[1]
function report-failure() {
    echo -e "\033[31m✗\033[m  $2, \033[1m$1\033[m args:"
    shift ; shift
    for var in "$@"; do
        echo "    - \"${var}\""
    done

    EXIT_CODE=1
    if [ ! -z ${break_on_fail} ]; then
        exit ${EXIT_CODE}
    fi
}
# ~\~ end
# ~\~ begin <<lit/index.md|assertions>>[0]
function assert-streq() {
    if [ "$2" = "$3" ]; then
        report-success "$1"
    else
        report-failure assert-streq "$@"
    fi
}
# ~\~ end
# ~\~ begin <<lit/index.md|assertions>>[1]
function assert-arrayeq() {
    local a1=($2)
    local a2=($3)
    local n=${#a1[@]}
    for (( i=0; i<${n}; i++)); do
        if [ ! "${a1[$i]}" = "${a2[$i]}" ]; then
            report-failure assert-arrayeq "$@"
            break
        fi
    done
    report-success "$1"
}        
# ~\~ end
# ~\~ begin <<lit/index.md|assertions>>[2]
function assert-exists() {
    if [ -e "$2" ]; then
        report-success "$1"
    else
        report-failure assert-exists "$@"
    fi
}
# ~\~ end
# ~\~ begin <<lit/index.md|assertions>>[3]
function assert-not-exists() {
    if [ ! -e "$2" ]; then
        report-success "$1"
    else
        report-failure assert-not-exists "$@"
    fi
}
# ~\~ end
# ~\~ begin <<lit/index.md|assertions>>[4]
function assert-return-fail() {
    if [ ! $2 -eq 0 ]; then
        report-success "$1"        
    else
        report-failure "$@"
    fi
}
# ~\~ end
# ~\~ begin <<lit/index.md|assertions>>[5]
function assert-return-success() {
    if [ $2 -eq 0 ]; then
        report-success "$1"        
    else
        report-failure "$@"
    fi
}
# ~\~ end
# ~\~ begin <<lit/index.md|setup>>[0]
function setup() {
    # ~\~ begin <<lit/index.md|create-temp-dir>>[0]
    TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'entangled-test')
    # ~\~ end
    # ~\~ begin <<lit/index.md|copy-relevant-files>>[0]
    echo "Setting up in ${TMPDIR} ..."
    cp "${DIR}"/* "${TMPDIR}"
    # ~\~ end
    # ~\~ begin <<lit/index.md|enter-temp-dir>>[0]
    pushd "${TMPDIR}" > /dev/null
    # ~\~ end
}
# ~\~ end
# ~\~ begin <<lit/index.md|teardown>>[0]
function teardown() {
    echo "Cleaning up ..."
    popd > /dev/null
    rm -rf "${TMPDIR}"
}
# ~\~ end
# ~\~ begin <<lit/index.md|run-test>>[0]
function run-test() {
     echo -e "\033[33m ~~~\033[m \033[1m$(basename $1 .test)\033[m \033[33m~~~\033[m"
     if [ -z ${no_setup} ]; then
         setup
     fi
     
     source "$(basename $1 .test).test"

     if [ -z ${no_setup} ]; then
         teardown
     fi
     echo
}
# ~\~ end
# ~\~ begin <<lit/index.md|show-help>>[0]
function show_help() {
    echo "usage: $0 [args]"
    echo
    echo "where [args] can be one of:"
    echo "    -h           help: show this help"
    echo "    -d           debug: run here instead of /tmp"
    echo "    -x           break on first failure"
    echo "    -u <unit>    only run unit"
    echo "    -c           clean after local run (with -d)"
    echo "    -v           verbose entangled"
    echo
    echo "Available units:"
    for t in *.test; do
            echo "    - $(basename ${t} .test)"
    done
}
# ~\~ end

# main script
# ~\~ begin <<lit/index.md|parse-command-line>>[0]
while getopts "hdxcvu:" arg
do
    case ${arg} in
    h)    show_help
          exit 0
          ;;
    # ~\~ begin <<lit/index.md|command-line-cases>>[0]
    d)    no_setup=1
          ;;
    # ~\~ end
    # ~\~ begin <<lit/index.md|command-line-cases>>[1]
    x)    break_on_fail=1
          ;;
    # ~\~ end
    # ~\~ begin <<lit/index.md|command-line-cases>>[2]
    u)    test_only=$(basename ${OPTARG} .test)
          ;;
    # ~\~ end
    # ~\~ begin <<lit/index.md|command-line-cases>>[3]
    v)    verbose=1
          ;;
    # ~\~ end
    # ~\~ begin <<lit/index.md|command-line-cases>>[4]
    c)    rm -fv "${DIR}"/entangled.db
          rm -fv "${DIR}"/*.scm
          git checkout "${DIR}"/*.md
          exit 0
          ;;
    # ~\~ end
    :)    echo "Invalid option: ${OPTARG} requires an argument"
          show_help
          exit 2
          ;;
    \?)   show_help
          exit 2
          ;;
    esac
done
# ~\~ end

if [ -z ${test_only} ]; then
    for unit in "${DIR}"/*.test; do
        run-test "${unit}"
    done
else
    if [ -f "${test_only}.test" ]; then
        run-test "${test_only}"
    else
        echo "Could not find test: ${test_only}"
    fi
fi

exit ${EXIT_CODE}
# ~\~ end
