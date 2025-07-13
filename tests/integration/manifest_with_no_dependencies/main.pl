:- use_module(bakage).
:- use_module('../../utils/testing.pl').
:- use_module('../../utils/assert.pl').

main :-
    run_tests.

test("test if no dependencies are installed", (pkg_install(X), test_eq(X, []))).
