# Deb-repository creation guide

## install nginx, gpg-agent, reprepro
    $ sudo apt-get update
    $ sudo apt-get install nginx gnupg-agent reprepro

## create nginx config
Replace SERVER_NAME placeholder with server name you will use.

    $ vim /etc/nginx/sites-available

    server {
        server_name             <SERVER_NAME>;
        listen                  <SERVER_NAME>:80;
        root                    /srv/www/repo;

        access_log              /var/log/nginx/<SERVER_NAME>.access.log;
        error_log               /var/log/nginx/<SERVER_NAME>.error.log;

        if ($host !~* ^(<SERVER_NAME>)$ ) {
            return 444;
        }

        location / {
            autoindex       on;
        }

        location /conf {
            deny            all;
        }

        location /db {
            deny            all;
        }
    }

## edit '~/.profile' for gpg-agent add
    if test -f $HOME/.gpg-agent-info && kill -0 `cut -d: -f 2 $HOME/.gpg-agent-info` 2> /dev/null; then
        GPG_AGENT_INFO=`cat $HOME/.gpg-agent-info`
        export GPG_AGENT_INFO
    else
            eval `gpg-agent --enable-ssh-support --daemon --write-env-file ~/.gpg-agent-info`
    fi

    if [ -f "${HOME}/.gpg-agent-info" ]; then
        . "${HOME}/.gpg-agent-info"
        export GPG_AGENT_INFO
        export SSH_AUTH_SOCK
        export SSH_AGENT_PID
    fi

## create directory for repo and repo`s conf
    $ sudo mkdir -p /srv/www/repo/conf

## create conf-files for repo
    $ sudo vim /srv/www/repo/conf/distributions
    Origin: <Origin here>
    Label: <Label here>
    Suite: stable
    Codename: trusty
    Architectures: i386 amd64
    Components: free
    Description: Description here
    SignWith: yes
    $ sudo vim /srv/www/repo/conf/option
    verbose
    ask-passphrase

## create GnuPG-key for repo
    $ sudo gpg --gen-key

## export GnuPG-key in asc
    $ cd /srv/www/repo
    $ sudo gpg --export -a KEY_ID >key.asc

## create repo
    $ cd /srv/www/repo
    $ sudo reprepro -b . includedeb trusty /path/to/files/*.deb

## restart nginx
    $ sudo service nginx reload
