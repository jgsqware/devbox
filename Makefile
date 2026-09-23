# devbox/Makefile — point d'entrée local, toujours à jour avant d'exécuter.
#
#   make                       git pull --ff-only puis ./bootstrap.sh
#   make ARGS="-n"             idem, en dry-run
#   make ARGS="--only ssh"     idem, une seule étape
#   make pull                  juste la mise à jour, sans lancer bootstrap
#   make bootstrap-only        lance bootstrap.sh sans pull (offline/debug)

.DEFAULT_GOAL := bootstrap
ARGS ?=

.PHONY: bootstrap pull bootstrap-only

bootstrap: pull bootstrap-only

pull:
	git pull --ff-only

bootstrap-only:
	./bootstrap.sh $(ARGS)
