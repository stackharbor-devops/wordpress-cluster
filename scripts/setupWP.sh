#!/bin/bash -e

purge=false;
pgcache=false;
objectcache=false;
edgeportCDN=false;
multisite=false;
domain=false;
url=false;
woocommerce=false;

SERVER_WEBROOT=/var/www/webroot/ROOT

ARGUMENT_LIST=(
    "purge"
    "pgcache"
    "objectcache"
    "edgeportCDN"
    "multisite"
    "CACHE_HOST"
    "CACHE_PORT"
    "CACHE_USER"
    "CACHE_PSWD"
    "CDN_URL"
    "CDN_ORI"
    "mode"
    "url"
    "domain"
    "ENV_NAME"
    "woocommerce"

)

WP=`which wp`

# read arguments
opts=$(getopt \
    --longoptions "$(printf "%s:," "${ARGUMENT_LIST[@]}")" \
    --name "$(basename "$0")" \
    --options "" \
    -- "$@"
)
eval set --$opts

while [[ $# -gt 0 ]]; do
    case "$1" in
        --purge)
            purge=$2
            shift 2
            ;;

        --pgcache)
            pgcache=$2
            shift 2
            ;;

        --objectcache)
            objectcache=$2
            shift 2
            ;;

        --edgeportCDN)
            edgeportCDN=$2
            shift 2
            ;;

        --CACHE_HOST)
            CACHE_HOST=$2
            shift 2
            ;;

        --CACHE_PORT)
            CACHE_PORT=$2
            shift 2
            ;;

        --CACHE_USER)
            CACHE_USER=$2
            shift 2
            ;;
            
        --CACHE_PSWD)
            CACHE_PSWD=$2
            shift 2
            ;;

        --CDN_URL)
            CDN_URL=$2
            shift 2
            ;;

        --CDN_ORI)
            CDN_ORI=$2
            shift 2
            ;;

        --multisite)
            multisite=$2
            shift 2
            ;;

        --mode)
            mode=$2
            shift 2
            ;;

        --url)
            url=$2
            shift 2
            ;;

        --domain)
            domain=$2
            shift 2
            ;;

        --ENV_NAME)
            ENV_NAME=$2
            shift 2
            ;;

	--woocommerce)
	    woocommerce=$2
	    shift 2
	    ;;

        *)
            break
            ;;
    esac
done

W3TC_OPTION_SET="${WP} w3-total-cache option set"
LSCWP_OPTION_SET="${WP} litespeed-option set"
lOG="/var/log/run.log"

COMPUTE_TYPE=$(grep "COMPUTE_TYPE=" /etc/jelastic/metainf.conf | cut -d"=" -f2)

cd ${SERVER_WEBROOT};

if [[ ${COMPUTE_TYPE} == *"llsmp"* || ${COMPUTE_TYPE} == *"litespeed"* ]] ; then
    CACHE_FLUSH="${WP} litespeed-purge all --path=${SERVER_WEBROOT}; rm -rf /var/www/webroot/.cache/vhosts/Jelastic/* "
    WPCACHE='lscwp';
elif [[ ${COMPUTE_TYPE} == *"lemp"* || ${COMPUTE_TYPE} == *"nginx"* ]] ; then
    CACHE_FLUSH="${WP} w3-total-cache flush all --path=${SERVER_WEBROOT}; /var/www/webroot/.cache/* "
    WPCACHE="w3tc";
else
    echo 'Compute type is not defined';
    exit;
fi

function generateCdnContent () {
    echo "wp-content/themes/twentytwentytwo/style.css" > ~/checkCdnContent.txt;
    echo "wp-includes/css/dist/block-library/style.min.css" >> ~/checkCdnContent.txt;
    echo "wp-includes/css/dist/block-library/theme.min.css" >> ~/checkCdnContent.txt;
    echo "wp-includes/js/wp-embed.min.js" >> ~/checkCdnContent.txt;
}

function checkCdnStatus () {
if [ $WPCACHE == 'w3tc' ] ; then
    CDN_ENABLE_CMD="${WP} w3-total-cache option set cdn.enabled true --type=boolean"
elif [ $WPCACHE == 'lscwp' ] ; then
    CDN_ENABLE_CMD="${WP} litespeed-option set cdn true"
fi
cat > ~/checkCdnStatus.sh <<EOF
#!/bin/bash
while read -ru 4 CONTENT; do
  status=\$(curl \$1\$CONTENT -k -s -f -o /dev/null && echo "SUCCESS" || echo "ERROR")
    if [ \$status = "SUCCESS" ]
    then
      continue
    else
      exit
    fi
done 4< ~/checkCdnContent.txt
cd ${SERVER_WEBROOT}
${CDN_ENABLE_CMD} --path=${SERVER_WEBROOT} &>> /var/log/run.log
${CACHE_FLUSH}  &>> /var/log/run.log
${WP} cache flush --path=${SERVER_WEBROOT} &>> /var/log/run.log
crontab -l | sed "/checkCdnStatus/d" | crontab -
EOF
chmod +x ~/checkCdnStatus.sh
PROTOCOL=$(${WP} option get siteurl --path=${SERVER_WEBROOT} | cut -d':' -f1)
crontab -l | { cat; echo "* * * * * /bin/bash ~/checkCdnStatus.sh ${PROTOCOL}://${CDN_URL}/"; } | crontab
}

if [ $purge == 'true' ] ; then
    ${CACHE_FLUSH} &>> /var/log/run.log
    ${WP} cache flush --path=${SERVER_WEBROOT} &>> /var/log/run.log
    [ -d /tmp/lscache/vhosts/ ] && /usr/bin/rm -rf /tmp/lscache/vhosts/Jelastic/* &>> /var/log/run.log
fi

if [ $pgcache == 'true' ] ; then
  case $WPCACHE in
    w3tc)
          $W3TC_OPTION_SET pgcache.enabled true --type=boolean --path=${SERVER_WEBROOT} &>> $lOG
          $W3TC_OPTION_SET pgcache.file.nfs true --type=boolean --path=${SERVER_WEBROOT} &>> $lOG
          ;;
    lscwp)
          ;;
  esac
fi

if [ $objectcache == 'true' ] ; then
  case $WPCACHE in
    w3tc)
          $W3TC_OPTION_SET objectcache.enabled true --type=boolean --path=${SERVER_WEBROOT} &>> /var/log/run.log
          $W3TC_OPTION_SET objectcache.engine memcached --path=${SERVER_WEBROOT} &>> /var/log/run.log
          $W3TC_OPTION_SET objectcache.memcached.servers ${CACHE_HOST}:${CACHE_PORT} --path=${SERVER_WEBROOT} &>> /var/log/run.log
          ;;
    lscwp)
          $LSCWP_OPTION_SET object true --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          $LSCWP_OPTION_SET object-kind 0 --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          
          $LSCWP_OPTION_SET object-host '' --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          [[ ! -z "${CACHE_HOST}" ]] && $LSCWP_OPTION_SET object-host ${CACHE_HOST} --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          
          $LSCWP_OPTION_SET object-port '' --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          [[ ! -z "${CACHE_PORT}" ]] && $LSCWP_OPTION_SET object-port ${CACHE_PORT} --path=${SERVER_WEBROOT} &>> /var/log/run.log;          
          ;;
  esac
fi

if [ $edgeportCDN == 'true' ] ; then
  if ! $(${WP} core is-installed --network --path=${SERVER_WEBROOT}); then
    case $WPCACHE in
      w3tc)
          generateCdnContent;
          checkCdnStatus;
          $W3TC_OPTION_SET cdn.enabled false --type=boolean --path=${SERVER_WEBROOT} &>> /var/log/run.log
          $W3TC_OPTION_SET cdn.engine mirror --path=${SERVER_WEBROOT} &>> /var/log/run.log
          $W3TC_OPTION_SET cdn.mirror.domain ${CDN_URL} --path=${SERVER_WEBROOT} &>> /var/log/run.log
          ;;
      lscwp)
          generateCdnContent;
          checkCdnStatus;
          CDN_ORI=$(${WP} option get siteurl --path=${SERVER_WEBROOT} | cut -d'/' -f3)
          PROTOCOL=$(${WP} option get siteurl --path=${SERVER_WEBROOT} | cut -d':' -f1)
          $LSCWP_OPTION_SET cdn false --path=${SERVER_WEBROOT} &>> /var/log/run.log
          $LSCWP_OPTION_SET cdn-mapping[url][0] ${PROTOCOL}://${CDN_URL}/ --path=${SERVER_WEBROOT} &>> /var/log/run.log
          $LSCWP_OPTION_SET cdn-ori "//${CDN_ORI}/" --path=${SERVER_WEBROOT} &>> /var/log/run.log
          ;;
    esac
  fi
fi

if [ $multisite == 'true' ] ; then
  cd ~/bin/ && ${WP} option update permalink_structure '' --path=/var/www/webroot/ROOT/ &>> /var/log/run.log;
  cd ~/bin/ && ${WP} rewrite structure '' --hard --path=/var/www/webroot/ROOT/ &>> /var/log/run.log;
  ${WP} cache flush --path=${SERVER_WEBROOT};
  case $WPCACHE in
    w3tc)
          ${WP} plugin deactivate w3-total-cache --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          [[ ${mode} == 'subdir' ]] && ${WP} core multisite-convert --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          [[ ${mode} == 'subdom' ]] && ${WP} core multisite-convert --path=${SERVER_WEBROOT} --subdomains &>> /var/log/run.log;
          ${WP} plugin activate w3-total-cache --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          ;;
    lscwp)
          # Stack Harbor: the network's object cache uses the backend and address the
          # single-site step configured (setupPlugins: --objectcache true with the kit's
          # CACHE_HOST/CACHE_PORT): Memcached, on the Standalone node's local socket
          # (/var/run/memcached/memcached.sock, port 0) or the Cluster's shared `cache`
          # node (port 11211). addons/multisite.jps calls this script without them, so
          # they are read back from the site's own LiteSpeed Cache options before the
          # conversion. Upstream wrote object-kind 1 (Redis) and /var/run/redis/redis.sock,
          # which these nodes do not run.
          if [[ -z "${CACHE_HOST}" ]]; then
            CACHE_HOST=$(${WP} option get litespeed.conf.object-host --path=${SERVER_WEBROOT} 2>>${lOG} || true)
            CACHE_PORT=$(${WP} option get litespeed.conf.object-port --path=${SERVER_WEBROOT} 2>>${lOG} || true)
          fi
          ${WP} plugin deactivate litespeed-cache --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          [[ ${mode} == 'subdir' ]] && ${WP} core multisite-convert --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          [[ ${mode} == 'subdom' ]] && ${WP} core multisite-convert --path=${SERVER_WEBROOT} --subdomains &>> /var/log/run.log;
          ${WP} plugin activate litespeed-cache --network --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          ${WP} cache flush --path=${SERVER_WEBROOT};
          # Network options through LiteSpeed Cache's own setter (Conf::network_update),
          # not raw SQL on wp_sitemeta: it writes the database AND the object cache that
          # caches site options. Then its files are rewritten from them in a fresh
          # process (Activation::update_files): the object-cache.php drop-in and
          # .litespeed_conf.dat, which the drop-in reads its backend from. Upstream's raw
          # UPDATE left the file on Memcached and the network options on Redis, so the
          # next settings save or plugin upgrade (both rewrite the file) moved the object
          # cache to a socket that does not exist and it stopped persisting (OBSERVED
          # 2026-10-13, sh-5 Standalone).
          echo "Configuring the network's LiteSpeed Cache (cache, object cache: ${CACHE_HOST:-none}:${CACHE_PORT:-})" >> /var/log/run.log;
          SH_OC_HOST="${CACHE_HOST}" SH_OC_PORT="${CACHE_PORT}" ${WP} eval '
            $c = \LiteSpeed\Conf::cls();
            $c->network_update("cache", 1);
            $h = (string) getenv("SH_OC_HOST");
            if ($h !== "") {
              $c->network_update("object", true);
              $c->network_update("object-kind", false);
              $c->network_update("object-host", $h);
              $c->network_update("object-port", (int) getenv("SH_OC_PORT"));
            }
          ' --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          ${WP} cache flush --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          ${WP} eval '\LiteSpeed\Activation::cls()->update_files();' --path=${SERVER_WEBROOT} &>> /var/log/run.log;
          ;;
  esac
  ${WP} cache flush --path=${SERVER_WEBROOT};
fi

if [ $url != 'false' ] ; then
  if ! $(${WP} core is-installed --network --path=${SERVER_WEBROOT}); then
    old_url=$(${WP} option get siteurl --path=${SERVER_WEBROOT})
    old_domain=$(${WP} option get siteurl --path=${SERVER_WEBROOT} | cut -d'/' -f3)
    new_domain=$(echo $url | cut -d'/' -f3)
    ${WP} search-replace "${old_url}" "${url}" --skip-columns=guid --all-tables --path=${SERVER_WEBROOT} &>> /var/log/run.log
    ${WP} search-replace "${old_domain}" "${new_domain}" --skip-columns=guid --all-tables --path=${SERVER_WEBROOT} &>> /var/log/run.log
    ${CACHE_FLUSH}  &>> /var/log/run.log
    ${WP} cache flush --path=${SERVER_WEBROOT} &>> /var/log/run.log
  fi
fi

if [ $domain != 'false' ] ; then
    old_domain=$(${WP} option get siteurl --path=${SERVER_WEBROOT} | cut -d'/' -f3)
    ${WP} search-replace "${old_domain}" "${domain}" --skip-columns=guid --all-tables --path=${SERVER_WEBROOT} &>> /var/log/run.log
    ${CACHE_FLUSH}  &>> /var/log/run.log
    ${WP} cache flush --path=${SERVER_WEBROOT} &>> /var/log/run.log
  if $(${WP} core is-installed --network --path=${SERVER_WEBROOT}); then
    ${WP} config set DOMAIN_CURRENT_SITE ${domain} --path=${SERVER_WEBROOT}
  fi
fi

if [ $woocommerce == 'true' ] ; then
  ${WP} plugin install woocommerce --activate --path=${SERVER_WEBROOT} &>> /var/log/run.log
fi
