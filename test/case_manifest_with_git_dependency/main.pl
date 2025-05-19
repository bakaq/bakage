:- use_module(pkg).
:- use_module('../util_packages/scryer_libs/packages/testing/testing.pl').
:- use_module(library(os)).
:- use_module(library(pio)).

main :-
    shell("rm -rf scryer_libs && rm -f manifest-lock.pl"),
    (
        run_tests([halt(false)])->
            Code=0
        ;   Code=1
    ),
    shell("rm -rf scryer_libs && rm -f manifest-lock.pl"), 
    halt(Code).

test("test dependencies are installed", (
        pkg_install(X),
        X = [
        install_dependency(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")))-success(true),
        lock(dependency("test", git("https://github.com/constraintAutomaton/test-prolog-package-manager.git")))-success(true)
        ]
    )
).

