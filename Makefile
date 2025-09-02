.PHONY: minimal converge logs lint

minimal:
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/minimal.yml

converge:
	ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/converge.yml

logs:
	tail -f /var/log/2047-ansible-pull.log

lint:
	ansible-lint ansible/

