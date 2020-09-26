
.PHONY: test
test:
	mix local.rebar --force
	mix local.hex --force
	mix deps.get
	SSH_HOST=openssh-server mix test --trace
