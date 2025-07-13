:- use_module(bakage).
:- use_module('../../utils/testing.pl').
:- use_module('../../utils/assert.pl').
:- use_module(library(pio)).
:- use_module(library(format)).

main :-
    pkg_install(_),
    run_tests.

test("the package report is valid", (
        pkg_install(X),
        Expected = [
            validate_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag"))))-success,
            do_nothing(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag"))))-success
        ],
        test_eq(X, Expected)
    )
).