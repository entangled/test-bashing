---
title: Test Bashing
subtitle: Writing integration tests in Bash?
author: Johan Hidding
---

Entangled is a command-line tool that is meant to be used from a shell like Bash. At some point I needed to test that the final executable is actually doing what it is supposed to do. This kind of testing is also known as integration testing. To do this testing I had several options:

- Use Haskell to run the commands and test everything
- Use Python since it is a bit more flexible
- Test directly from Bash

Testing in Haskell is usually done using `Hspec` together with `QuickCheck`. `Hspec` manages the overall testing architechture, while `QuickCheck` lets you do property testing. This all works very well with functional code, but we're in the realm of shell scripting here: setting up an environment, do mutations, check for sanity. Somehow the prospect of coding all this up in Haskell does not sound enticing.

Python would be a nice hybrid. It has unit-testing libraries available, and all the power of a generic language. In the end however, what I want to do is, have a markdown file, emulate it being written to using `patch`, check if entangled shows the correct behaviour. The tests should look like a user typing in commands, working in the editor. I ended up coding this in Bash; a decision I may come to regret, but until that time, here's how it works.

# Command line interface in Bash
Command line parsing in Bash is actually quite nice.

``` {.bash #parse-command-line}
while getopts "hdxcvu:" arg
do
    case ${arg} in
    h)    show_help
          exit 0
          ;;
    <<command-line-cases>>
    :)    echo "Invalid option: ${OPTARG} requires an argument"
          show_help
          exit 2
          ;;
    \?)   show_help
          exit 2
          ;;
    esac
done
```

This loops over command line arguments and looks for any argument matching the `"hdxcvu:"` description, that is, all these arguments are flags, except for `u` which expects an extra parameter. The `-h` flag runs the `show_help` function and exits. If an option is not recognized, we `show_help` and exit with error code.

The `-d` flag runs unit tests in the current directory without first running `setup`.

``` {.bash #command-line-cases}
d)    no_setup=1
      ;;
```

The `-x` flag breaks off the script at the first test that fails.

``` {.bash #command-line-cases}
x)    break_on_fail=1
      ;;
```

The `-u` parameter singles out a test to run.

``` {.bash #command-line-cases}
u)    test_only=$(basename ${OPTARG} .test)
      ;;
```

The `-v` flag runs verbose.

``` {.bash #command-line-cases}
v)    verbose=1
      ;;
```

The `-c` flag cleans current directory (after tests have been run with `-d`), by running `git checkout`.

``` {.bash #command-line-cases}
c)    rm -fv "${DIR}"/entangled.db
      rm -fv "${DIR}"/*.scm
      git checkout "${DIR}"/*.md
      exit 0
      ;;
```

## Help message

``` {.bash #show-help}
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
```

# Running tests
Each test is located in a file with the `.test` extension. These are Bash files, but since they do not function outside the context of this testing framework, I decided to give them a different extension. If you put `# vim:ft=bash` as the last line of the file, Vim will recognize it as a Bash script. The `run-test()` function takes as an argument either the name of the test or the corresponding filename with the `.test` extension. First `setup()` is called, then the test is sourced, after wich `teardown()` is called.

``` {.bash #run-test}
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
```

## Setup and Teardown
Each test is run in an isolated environment created in a temporary directory. We set this up using the `setup()` function.

``` {.bash #setup}
function setup() {
    <<create-temp-dir>>
    <<copy-relevant-files>>
    <<enter-temp-dir>>
}
```

To create a temporary directory, UNIX has the `mktemp` command. This command may differ slightly between Linux and Mac though, this hack solves that issue.

``` {.bash #create-temp-dir}
TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'entangled-test')
```

Then we populate the temporary directory with all the files needed to run the test. Here we just copy everything from the current directory.

``` {.bash #copy-relevant-files}
echo "Setting up in ${TMPDIR} ..."
cp "${DIR}"/* "${TMPDIR}"
```

To enter the directory we use `pushd`. 

``` {.bash #enter-temp-dir}
pushd "${TMPDIR}" > /dev/null
```

This allows us to get back to current working directory by running `popd`. The `teardown()` function does exactly that, and removes the temporary directory.

``` {.bash #teardown}
function teardown() {
    echo "Cleaning up ..."
    popd > /dev/null
    rm -rf "${TMPDIR}"
}
```

# The main script
The main script has to know where it is located. The following one-liner puts the name of the directory containing the script that is being run in `${DIR}`. There are other ways, but this has the advantage of also working on MacOS.

``` {.bash #get-script-dir}
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
```

We are running all test by default. If any test fails, `EXIT_CODE` has to be set to `1`.

``` {.bash #define-exit-code}
EXIT_CODE=0
```

``` {.bash file=test/run.sh}
# taste environment
<<get-script-dir>>
<<define-exit-code>>

# function definitions
<<reporting>>
<<assertions>>
<<setup>>
<<teardown>>
<<run-test>>
<<show-help>>

# main script
<<parse-command-line>>

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
```

# Reporting
In the case of a test succeeding, print a message with a green `✓`. Argument `$1` describes the test.

``` {.bash #reporting}
function report-success() {
    echo -e "\033[32m✓\033[m  $1"
}
```

If a test fails, we print a message explaining the failure with a red `✗`. Argument `$1` is the name of the assertion, argument `$2` the description of the test, the rest are arguments to the failed assertion.

``` {.bash #reporting}
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
```

# Assertions

``` {.bash #repl}
<<reporting>>
<<assertions>>
```

The first argument of an assertion is always the human-readable description. The following assertions are defined.

## String equality
Test if two strings are equal.

``` {.bash .eval #repl}
assert-streq "6 * 7 == 42" $(echo "6 * 7" | bc) "42"
```

``` {.bash .eval #repl}
assert-streq "Time is an illusion" "Thursday" "Friday"
```

Implementation:

``` {.bash #assertions}
function assert-streq() {
    if [ "$2" = "$3" ]; then
        report-success "$1"
    else
        report-failure assert-streq "$@"
    fi
}
```

## Array equality
Tests wether the arrays in arguments `$2` and `$3` are equal by string comparison, for example when listing expected files. Do make sure to use `sort`.

``` {.bash}
assert-arrayeq "Source contains expected files" \
    "$(entangled list | sort)" "factorial.scm hello.scm"
```

Implementation:

``` {.bash #assertions}
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
```

## File existence
Tests wether a given file exists.

``` {.bash #repl .eval}
assert-exists "hello.txt exists" hello.txt
touch hello.txt
assert-exists "hello.txt was created" hello.txt
rm hello.txt
assert-not-exists "hello.txt was destroyed" hello.txt
```

Implementation:

``` {.bash #assertions}
function assert-exists() {
    if [ -e "$2" ]; then
        report-success "$1"
    else
        report-failure assert-exists "$@"
    fi
}
```

The following succeeds if the given filename does not exist.

``` {.bash #assertions}
function assert-not-exists() {
    if [ ! -e "$2" ]; then
        report-success "$1"
    else
        report-failure assert-not-exists "$@"
    fi
}
```

## Command success
To test wether the previous command returned success by calling these functions with `$?` argument.

``` {.bash #repl .eval}
which entangled
assert-return-success "Entangled executable found" $?
```

The `assert-return-fail` function succeeds if the command failed (exit code other than 0).

``` {.bash #assertions}
function assert-return-fail() {
    if [ ! $2 -eq 0 ]; then
        report-success "$1"        
    else
        report-failure "$@"
    fi
}
```

The `assert-return-success` function succeeds if the command return success (exit code 0).

``` {.bash #assertions}
function assert-return-success() {
    if [ $2 -eq 0 ]; then
        report-success "$1"        
    else
        report-failure "$@"
    fi
}
```
