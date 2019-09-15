#!/bin/bash

#Funciones principales
# Baja automáticamente las series que pongamos en el array SERIES. El trigger es que se publique en últimas descargas. Notificación por telegram de la descarga, la portada y el número total de episodios.
# Si se sube el capítulo 1 de la temporada 1 de alguna serie, si la puntuación es mayor de 7 en IMDB, nos notifica  traduciendo la sinopsis al español si existe la herrameinta 'trans' y con el enlace a la ficha en IMDB.
#Alerta de todas las series de las que se suba el primer capítulo de cualquier temporada.
# Comprueba las peliculas en microHD y si hay alguna con puntuación >7 en IMDB, nos notifica a Telegram (no lo descarga automáticamente) con el enlace al archivo torrent y a la ficha de IMDB.
# Notifica lo que tenga más de un 8 (en IMDB) que se sube a Netflix, HBO o Amazon Primer Video


#Dominios alternativos:
# descargas2020.com
# pctnew.com

#Dominio principal
DOMINIO="descargas2020.org"


#Array con las series a descargar
SERIES=( suits chicago-fire modern-family big-bang-theory hanna killing-eve mr-mercedes awake nuestro-planeta juego-de-tronos como-defender-a-un-asesino chernobyl the-society )

#Ruta de trabajo
RUTA="/opt/descargas2020"

#Notificaciones telegram
TELEGRAMAPIKEY="bot123456789:1234567890ABCDEFGHIJKLMNO"
TELEGRAMCHANNEL="-123456789"

#API de ThemovieDB para la descarga de la portada y número de capítulos
TMDBKEY="1234567890ABCDEFGHIJKLMNO"

#Función de búsqueda en IMDB
infoIMDB () {
    IMDBID="$(curl --max-time 60 -s https://www.imdb.com/find?q="$(tr '-' '+' <<< $1 | tr ' ' '+' )"\&s=tt | tr [:space:] \\n | grep 'href="/title/' | grep -v "ref_=nv_mv_dflt" | head -1 | cut -d '/' -f3)"
    PUNTUACION="$(curl --max-time 60 -s https://www.imdb.com/title/$IMDBID/ | grep -o 'title="[0-9]*.[0-9]* based' | sed 's/title="//g' | cut -d' ' -f1 | tr '.' ',')"
    #Error si no se obtienen datos de IMDB
    if [ -z $IMDBID ] || [ -z $PUNTUACION ];then
    
        curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="⚠️   Error al descargar info de IMDB para $1" -F parse_mode=markdown
    fi

}



#Comprobamos que existen las carpetas necesarias
if ! [ -w $RUTA/poster ] || ! [ -w $RUTA/torrents ]; then
  echo "Las carpetas $RUTA/torrents y $RUTA/poster deben existir y tener permiso de escritura"
  exit 1
fi


#Descargamos la página 1 y 2 de últimas descargas
if ! curl --max-time 60 -s https://descargas2020.org/ultimas-descargas/ | grep --text "serie-en-hd\|cine-alta-definicion-hd\|peliculas-x264-mkv/" | sed 's/</\n/g' | sed 's/ /\n/g' | grep -i --text "serie-en-hd/\|cine-alta-definicion-hd/\|peliculas-x264-mkv/" | uniq | sed 's/href="//g' | tr -d '"' | grep -ve "peliculas-x264-mkv/$" > /tmp/descargas2020.feed ;  then
    curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="⚠️  Error al descargar el feed de ${DOMINIO}"
    exit 1

else

    #Segunda página

    curl --max-time 60 -s https://descargas2020.org/ultimas-descargas/pg/2 | grep --text "serie-en-hd\|cine-alta-definicion-hd\|peliculas-x264-mkv/" | sed 's/</\n/g' | sed 's/ /\n/g' | grep -i --text "serie-en-hd/\|cine-alta-definicion-hd/\|peliculas-x264-mkv/" | uniq | sed 's/href="//g' | tr -d '"' | grep -ve "peliculas-x264-mkv/$" >> /tmp/descargas2020.feed

fi


#######################################
# COMPROBAMOS LAS SERIES QUE SEGUIMOS
#######################################

#Bucle que recorre el array 'SERIES'
for SERIE in "${SERIES[@]}"
do

    echo "Comprobando $SERIE"
    #Dejamos solo las líneas del feed nuevas desde la última ejecución y lo recorremos en un bucle
    cat /tmp/descargas2020.feed | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep descargar/serie-en-hd  | while read DESCARGA
    do
     
        #Comprobamos si coincide con alguna de las series que queremos bajar
        if [[ $DESCARGA =~ $SERIE ]]; then

            #Tenemos coincidencia
            echo "Tenemos coincidencia. Hacemos la descarga de $DESCARGA"

            #Extraemos la temporada y capítulo desde la URL del feed:
            SERIE="$( cut -d'/' -f6 <<< $DESCARGA | cut -d '-' -f1- )"
   
            TEMPORADA="$( cut -d'/' -f7 <<< $DESCARGA | cut -d '-' -f2 )"
            CAPITULO="$( cut -d'/' -f8 <<< $DESCARGA | cut -d '-' -f2- )"
                
            #Themoviedatabase desde una script externo, y lo mete en un array 
            INFO=( $(/opt/smartmirrorPI/descargas2020/info_themoviedb.sh `tr '-' '+' <<< $SERIE` $TEMPORADA) )

            POSTER="${INFO[3]}"
            echo "Poster desde API de TMDB $POSTER"
            POSTER_URL="http://image.tmdb.org/t/p/w500/${POSTER}"
            echo "Poster desde API de TMDB $POSTER_URL"
            TOTAL_EPISODIOS=${INFO[1]}
            echo "Tiene $TOTAL_EPISODIOS episodios" 

            if [[ $SERIE =~ "sevda" ]]; then
                SERIE="$SERIETMP"
            fi

            #Descarga del poster si no existe ya
            if ! ls $RUTA/poster/$POSTER
             then
                echo "Descargando portada de $SERIE..."
                cd $RUTA/poster/
                wget `tr -d \\ <<< $POSTER_URL`
                cd -

            else
                echo "La portada ya está bajada. Saltamos la descarga."
            fi

     
            #Entramos en la página de la descarga del capítulo y obtenemos el nombre del torrent, quitando espacios y texto que sobra
            TORRENT=$(curl --silent --max-time 10 -L "https://${DOMINIO}/descargar/serie-en-hd/$SERIE/temporada-$TEMPORADA/capitulo-$CAPITULO/#" | grep -a "window.location.href ="  |  cut -f2 -d"\"" |rev | cut -c 2- | rev |cut -c 39- )
            echo "Torrent: $TORRENT"
            TORRENT_URL="https://${DOMINIO}/download/${TORRENT}.torrent"
            MQTT_URL="https:/maniattico.com"    #Esto es un proxy MQTT para que al pulsar se descargue o haga alguna acciones


            #Si la variable TORRENT está a null (el enlace no se ha encontrado)
            if [ -z $TORRENT ]; then
                echo "Archivo no disponible o error: https://${DOMINIO}/descargar/serie-en-hd/$SERIE/temporada-$TEMPORADA/capitulo-$CAPITULO/#"
                curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="⚠️  Archivo no disponible o error: https://${DOMINIO}/descargar/serie-en-hd/$SERIE/temporada-$TEMPORADA/capitulo-$CAPITULO/#"
                continue
            fi

            #Si el capítulo a descargar y el total coinciden, es el último de la temporada
            if [ $TOTAL_EPISODIOS = $CAPITULO ]; then
                EXTRA_INFO="*Ultimo capitulo de la temporada $TEMPORADA*"
            else
                EXTRA_INFO=""
            fi
 

            #Descargamos
            cd $RUTA/torrents/ 
            wget --timeout=15 $TORRENT_URL 


            #Copiamos a 'autodescargas' del servidor del salón
            if /usr/bin/smbclient //192.168.1.112/autodescarga -usuarios%password -c "put ${TORRENT}.torrent"; then

                echo "Copia al servidor Windows completada con éxito"
                rm -f ${TORRENT}.torrent

                #Telegram OK. Comprobamos que exista la carátula, si no mandamos solo texto (para que el Telegram llegue bien)
                if ! [ -z $POSTER ]; then
                    echo "Enviamos telegram con poster: `cut -d '/' -f2 <<< $POSTER`"
                    curl  -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendPhoto -F chat_id=$TELEGRAMCHANNEL -F photo=@$RUTA/poster/`cut -d '/' -f2 <<< $POSTER` -F caption="Descargando *$(tr '[:lower:]' '[:upper:]' <<< $SERIE)* \`s${TEMPORADA}e${CAPITULO}\` - total: $TOTAL_EPISODIOS episodios. $EXTRA_INFO" -F parse_mode=markdown

                else

                    echo "Enviamos telegram sin poster"
                    curl  -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="Descargando *$(tr '[:lower:]' '[:upper:]' <<< $SERIE)* \`s${TEMPORADA}e${CAPITULO}\` - total: $TOTAL_EPISODIOS episodios. $EXTRA_INFO"

                fi

            else
                #Si falla algo al copiar por SMB, envía un telegram con un enlace de reintento.
                
                echo "Enviamos por telegram error de que nos e ha copiado"
                curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="⚠️  Error al copiar el torrent *$SERIE* s${TEMPORADA}e${CAPITULO} a la carpeta autodescarga. [REINTENTAR]($MQTT_URL)" -F parse_mode=markdown

            fi

 
       
            
        fi

    done
done






#######################################
# COMPROBAMOS SERIES NUEVAS (S01E01)
#######################################


#Saca las nuevas series que han subido (temporada 1 capitulo 1), y envia notificación de las que tengan más de un 7 en IMDB
echo "Comprobando si hay alguna serie nueva..."

cat /tmp/descargas2020.feed | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep serie-en-hd | grep descargar | grep temporada-1 | grep capitulo-01 | cut -d '/' -f6 | while read SERIENUEVA
do
    echo "Comprobando $SERIENUEVA"

    infoIMDB "$SERIENUEVA"

    MQTT_URL="https://maniattico.com"

    curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="📺 Nueva serie disponible: [$(tr '-' ' ' <<< $SERIENUEVA | tr '[:lower:]' '[:upper:]' )](https://www.imdb.com/title/$IMDBID/) - ${PUNTUACION}⭐ *+* [Agregar a descargas automaticas]($MQTT_URL)" -F parse_mode=markdown
    
done




#######################################
# COMPROBAMOS TEMPORADAS NUEVAS (S*E01)
#######################################


#Saca las nuevas series que han subido (capitulo 1 de cualquier temporada), y envia notificación por si se nos ha pasado una de las nuestras
echo "Comprobando si hay alguna temporada nueva de cualquier serie..."

cat /tmp/descargas2020.feed | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep serie-en-hd | grep descargar | grep capitulo-01 | cut -d '/' -f6,7,8 | while read TEMPORADANUEVA
do
    SERIE="$(cut -d '/' -f1 <<< $TEMPORADANUEVA)"
    TEMPORADA="$(cut -d '/' -f2 <<< $TEMPORADANUEVA | cut -d '-' -f2- )"
    CAPITULO="$(cut -d '/' -f3 <<< $TEMPORADANUEVA | cut -d '-' -f2- )"
    MQTT_URL="https://maniattico.com"

    echo "Encontrada temporada $TEMPORADA, capitulo $CAPITULO de $SERIE"


    curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="📺 Disponible capitulo 1 de la *${TEMPORADA}ª* temporada de *$(tr '-' ' ' <<< $SERIE | tr '[:lower:]' '[:upper:]' )*   ---   *+* [Agregar a descargas automaticas]($MQTT_URL)" -F parse_mode=markdown
    

done



#######################################
# COMPROBAMOS LAS PELICULAS
#######################################

#Saca las nuevas peliculas en MicroHD, y envia notificación de las que tengan más de un 7 en IMDB
echo "Comprobando peliculas..."

cat /tmp/descargas2020.feed | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep "peliculas-x264-mkv" | cut -d '/' -f6 | while read PELICULA
do
    echo "Comprobando $PELICULA"

    infoIMDB "$PELICULA"

    #Solo nos quedamos con las de más de un 7
    if [[ $( cut -d ',' -f1 <<< $PUNTUACION ) -lt 6 ]] && ! [ -z $PUNTUACION ]; then

        echo "$PUNTUACION 💩 - No hacemos nada"

    else

        #Entramos en la página de la descarga del capítulo y obtenemos el nombre del torrent, quitando espacios y texto que sobra
        TORRENT=$(curl --silent --max-time 10 -L "https://descargas2020.org/descargar/peliculas-x264-mkv/$PELICULA/" | grep -a "window.location.href ="  |  cut -f2 -d"\"" |rev | cut -c 2- | rev |cut -c 39-)
        TORRENT_URL="https://${DOMINIO}/doenload/${TORRENT}.torrent"
        MQTT_URL="https://maniattico.com"

        curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="🍿 Disponible nueva peli en HD: [$(tr '-' ' ' <<< $PELICULA | tr '[:lower:]' '[:upper:]' )](https://www.imdb.com/title/$IMDBID/) ${PUNTUACION}⭐ ---    🔗[DESCARGAR]($MQTT_URL)" -F parse_mode=markdown

    fi

done





##############################################


#Guardamo la primera entrada de ${DOMINIO} para cortar ahí la próxima vez, escapando las barras para el siguiente sed
cat /tmp/descargas2020.feed | head -n 1 | sed 's/\//\\\//g' > $RUTA/ultimo.feed






##############################################
# ESTRENOS DE SERIES EN NETFLIX, HBO y AMAZON
##############################################

#Saca un listado de estrenos de Netflix, HBO y Amazon PrimeVideo, que tengan más de una puntuación en IMDB ordenado por fecha de publicación

#Puntuación mínima de IMDB para notificar
IMDBRATING=8

SERVICIO_ARRAY=( netflix hbo amazon )

for SERVICIO in "${SERVICIO_ARRAY[@]}"
do

    echo ""
    echo "Comprobando estrenos de $SERVICIO"

        
    curl -s "https://reelgood.com/tv/source/$SERVICIO?filter-imdb_start=$IMDBRATING&filter-sort=3" | sed 's/>/>\n/g' | tr '{' \\n | grep -e '^"title":' | cut -d '"' -f4 | sed "/$(cat $RUTA/ultimo.$SERVICIO)/Q" | while read SERIE
        do

            if ! [[ -z $SERIE ]]; then    
                infoIMDB "$SERIE"

                echo "$SERVICIO: $SERIE - $PUNTUACION"
                
                curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="📣 Nuevo en $SERVICIO: [$(tr '-' ' ' <<< $SERIE | tr '[:lower:]' '[:upper:]' )](https://www.imdb.com/title/$IMDBID) - ${PUNTUACION}⭐" -F parse_mode=markdown
            fi
        done

        #Guardamo la primera entrada para cortar ahí la próxima vez, escapando las barras para el siguiente sed
        curl -s "https://reelgood.com/tv/source/$SERVICIO?filter-imdb_start=$IMDBRATING&filter-sort=3" | sed 's/>/>\n/g' | tr '{' \\n | grep -e '^"title":' | cut -d '"' -f4 | head -1 | sed 's/\//\\\//g'  > $RUTA/ultimo.$SERVICIO


done
