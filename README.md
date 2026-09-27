# autossh

Puppet module that deploys, manages and removes persistent reverse or local SSH tunnels with
[autossh](https://www.harding.motd.ca/autossh/), one systemd unit per tunnel.

## What it does

- Installs the `autossh` package.
- Creates a locked-down `autossh` system user and generates its SSH key
  (`/home/autossh/.ssh/puppet_autossh`). Copy the public key to the remote host's
  `authorized_keys` for the `autossh` user.
- For each entry in the `autossh::config` Hiera hash, writes
  `/etc/systemd/system/<name>.service` and keeps the service running.

## Requirements

- `puppetlabs-accounts` and `puppet-ssh_keygen` from the Forge.
- A `string_to_port` function in your control repo (derives a stable autossh monitor port
  per tunnel). Example: `lib/puppet/functions/string_to_port.rb` in
  [puppet-homelab-public](https://github.com/ethan-c-houghton/puppet-homelab-public).

## Usage

```puppet
include autossh
```

Single binding:

```yaml
autossh::config:
  puppet_proxy:
    forward_type: 'remote'   # 'remote' (-R) or 'local' (-L)
    local_port: '8140'
    remote_port: '8141'
    remote_host: 'proxy.example.com'
```

Several bindings over one tunnel:

```yaml
autossh::config:
  wazuh_proxy:
    remote_host: 'proxy.example.com'
    bindings:
      agent:
        forward_type: 'remote'
        remote_port: 1513
        local_port: 1514
      enrollment:
        forward_type: 'remote'
        remote_port: 1516
        local_port: 1515
```

Set `enabled: false` on a tunnel to stop and disable its service.
