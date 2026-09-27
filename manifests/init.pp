class autossh (
  String $ssh_filename = "/home/autossh/.ssh/puppet_autossh"
) {
  package { 'autossh':
    ensure => 'present',
  }
  # Puppet will manage the ssh key creation, but it will be up to the user to get the public key and add it to the remote host's yaml
  accounts::user { 'autossh':
    uid        => '80085',
    gid        => '80085',
    shell      => '/usr/sbin/nologin',
    password   => '!!',
    locked     => false,
    managehome => true,
  }
  ssh_keygen { 'autossh':
    filename => $ssh_filename,
    comment  => "puppet_autossh_${facts['hostname']}",
    user     => 'autossh',
    require  => Accounts::User['autossh'], # creates ~/.ssh (managehome)
  }
  file { '/home/autossh/.ssh/known_hosts':
    ensure  => file,
    owner   => 'autossh',
    mode    => '0644',
    require => Accounts::User['autossh'],
  }
  $config = lookup('autossh::config', Hash, 'deep', {})
  $config.each |String $proxy_name, Hash $proxy_config| {
    $monit_port = string_to_port("${facts['hostname']}_${proxy_name}", 50000, 51000)
    # Create port binding configurations - normalize single config to array format
    $bindings = 'bindings' in $proxy_config ? {
      true  => $proxy_config['bindings'].values(),
      false => [$proxy_config]
    }

    # Generate SSH port forwarding arguments
    $port_bindings = $bindings.map |Hash $config| {
      $flag = $config['forward_type'] ? {
        'remote' => 'R',
        'local'  => 'L',
        default  => fail("Unknown forward_type: ${config['forward_type']}")
      }
      "-${flag} ${config['remote_port']}:localhost:${config['local_port']}"
    }.join(' ')

    $host_key = $proxy_config['host_key']
    $host_key_options = $host_key ? {
      undef   => '-o StrictHostKeyChecking=accept-new',
      default => '-o StrictHostKeyChecking=yes',
    }

    if $host_key and !defined(Sshkey[$proxy_config['remote_host']]) {
      sshkey { $proxy_config['remote_host']:
        ensure  => present,
        type    => $host_key['type'],
        key     => $host_key['key'],
        target  => '/home/autossh/.ssh/known_hosts',
        require => File['/home/autossh/.ssh/known_hosts'],
      }
    }

    file { "/etc/systemd/system/${proxy_name}.service":
      ensure  => file,
      content => epp("${module_name}/autossh_conf.epp", {
          'proxy_name'       => $proxy_name,
          'monit_port'       => $monit_port,
          'identity_file'    => $ssh_filename,
          'port_bindings'    => $port_bindings,
          'remote_host'      => $proxy_config['remote_host'],
          'host_key_options' => "-o UserKnownHostsFile=/home/autossh/.ssh/known_hosts ${host_key_options}",
      }),
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      notify  => Exec["systemd-reload-${proxy_name}"],
    }
    exec { "systemd-reload-${proxy_name}":
      command     => '/bin/systemctl daemon-reload',
      refreshonly => true,
      notify      => Service[$proxy_name],
    }
    service { $proxy_name:
      ensure    => pick($proxy_config['enabled'], true),
      enable    => pick($proxy_config['enabled'], true),
      subscribe => File["/etc/systemd/system/${proxy_name}.service"],
      require   => [
        File["/etc/systemd/system/${proxy_name}.service"],
        Exec["systemd-reload-${proxy_name}"],
        Ssh_keygen['autossh'],
      ],
    }
  }
}
