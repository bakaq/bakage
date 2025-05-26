:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module(library(ordsets)).

main :-
    run_tests.
  
test("the package report is valid", (
        pkg_install(X),
        list_to_ord_set(X, X_Set),
        list_to_ord_set([
        install_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")))-success,
        install_dependency(dependency("test_branch", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", branch("branch"))))-success,
        install_dependency(dependency("test_tag", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", tag("tag"))))-success,
        install_dependency(dependency("test_hash", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git", hash("d19fefc1d7907f6675e181601bb9b8b94561b441"))))-success,
        install_dependency(dependency("test_local", path("./local_package")))-success,
        install_dependency(dependency("error", path("./bar")))-error(_)
        ], Expected),
        X_Set = Expected
    )
).