
permissions:
	cd test/fixture/config/ssh_host_keys; chmod 600 ssh_host_dsa_key ssh_host_ecdsa_key ssh_host_ed25519_key ssh_host_rsa_key


.PHONY: test
test:
	mix local.rebar --force
	mix local.hex --force
	mix deps.get
	SSH_HOST=openssh-server mix test --trace
