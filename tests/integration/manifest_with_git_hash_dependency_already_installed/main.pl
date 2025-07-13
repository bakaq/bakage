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
            validate_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))))-success,
            do_nothing(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))))-success
        ],
        test_eq(X, Expected)
    )
).