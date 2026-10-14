## This project's base for every suite: the kit harness plus this game's own
## fixtures and helpers. Every suite extends it by path:
##     extends "res://{{TEST_DIR}}/lib/project_suite.gd"
## (the test folder is .gdignore'd, so class_name would not register).
##
## Write shared setup here once instead of in every suite, for example:
## - load_arena(): spawn a flat arena scene from {{TEST_DIR}}/fixtures/ with
##   spawn markers, so level redesigns never break mechanics tests,
## - disable_ai(actor): stop an AI mind so only the test drives the actor,
## - helpers that give actors test-owned stats (huge health, known attack).
extends "res://{{KIT}}/harness/test_suite.gd"
