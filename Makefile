.PHONY: init deps

init:
	iex -S mix

deps:
	mix deps.get
