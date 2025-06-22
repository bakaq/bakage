:- use_module(bakage).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module('../util_packages/assert.pl').
:- use_module(library(pio)).
:- use_module(library(format)).

main :-
    pkg_install(_),
    run_tests.

test("the package report is valid", (
        pkg_install(X),
        Expected = [
            validate_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")))-success,
            do_nothing(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")))-success
        ],
        test_eq(X, Expected)
    )
).