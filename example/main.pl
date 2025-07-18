% Loads the package loader
:- use_module(bakage).

% Loads a package. The argument should be an atom equal to the name of the
% dependency package specified in the `name/1` field of its manifest.
:- use_module(pkg(testing)).
:- use_module(pkg(test_branch)).
:- use_module(pkg(test_tag)).
:- use_module(pkg(test_hash)).
:- use_module(pkg(test_local)).

% You can then use the predicates exported by the main file of the dependency
% in the rest of the program.

main :-
    % `run_tests/0` is exported by `pkg(testing)`
    run_tests,
    halt.

test("test if the branch dependency works", (tag(exist))).
test("test if the tag dependency works", (branch(exist))).
test("test if the hash dependency works", (hash(exist))).
test("test if the local dependency works", (local(exist))).
