#!/bin/bash

#Funciones principales
# Baja automáticamente las series que pongamos en el array SERIES. El trigger es que se publique en el feed RSS. Notificación por telegram de la descarga, la portada y el número total de episodios.
# Si se sube el capítulo 1 de la temporada 1 de alguna serie, si la puntuación es mayor de 7 en IMDB, nos notifica, traduciendo la sinopsis al español si existe la herrameinta 'trans' y con el enlace a la ficha en IMDB.
# Comprueba las peliculas en microHD y si hay alguna con puntuación >7 en IMDB, nos notifica a Telegram (no lo descarga automáticamente) con el enlace al archivo torrent y a la ficha de IMDB.


#Array con las series a descargar
SERIES=( suits chicago-fire modern-family big-bang-theory)

#Ruta de trabajo
RUTA="/opt/descargas2020"

#Notificaciones telegram
TELEGRAMAPIKEY="bot000000000:0000000000000000000000000000000000"
TELEGRAMCHANNEL="-000000000"

#API de ThemovieDB para la descarga de la portada
TMDBKEY="00000000000000000000000000000000000"

#Comprobamos que existen las carpetas necesarias
if ! [ -w $RUTA/poster ] || ! [ -w $RUTA/torrents ]; then
  echo "Las carpetas $RUTA/torrents y $RUTA/poster deben existir y tener permiso de escritura"
  exit 1
fi



#Descargamos el feed completo actual para trabajar offline o avisamos por telegram si hay error
curl https://descargas2020.com/feed --silent > /tmp/descargas2020.feed || curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="⚠️  Error al descargar el feed de descargas2020.com/feed"




#######################################
# COMPROBAMOS LAS SERIES QUE SEGUIMOS
#######################################

#Bucle que recorre el array 'SERIES'
for SERIE in "${SERIES[@]}"
do

    echo "Comprobando $SERIE"
    #Dejamos solo las líneas del feed nuevas desde la última ejecución y lo recorremos en un bucle
    cat /tmp/descargas2020.feed | sed -n 's:.*<link>\(.*\)</link>.*:\1:p'  | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep descargar/serie-en-hd  | while read DESCARGA
    do
     
            #Comprobamos si coincide con alguna de las series que queremos bajar
        if [[ $DESCARGA =~ $SERIE ]]; then
            #Tenemos coincidencia

            echo "Tenemos coincidencia. Hacemos la descarga de $DESCARGA"

            #Extraemos la temporada y capítulo desde la URL del feed:
            SERIE="$( cut -d'/' -f6 <<< $DESCARGA | cut -d '-' -f1- )"
            TEMPORADA="$( cut -d'/' -f7 <<< $DESCARGA | cut -d '-' -f2 )"
            CAPITULO="$( cut -d'/' -f8 <<< $DESCARGA | cut -d '-' -f2- )"
                
            #Themoviedatabase    
            #Volcamos resultado para trabajar offline
            curl -s --request GET --url "https://api.themoviedb.org/3/search/tv?query=$SERIE&season_number=$TEMPORADA&language=es-ES&api_key=$TMDBKEY" --header 'content-type: application/json' --data '{}' | tr ',' "\n" > $RUTA/api_buscar.log

            TMDBID=`cat $RUTA/api_buscar.log | grep '"id":' | head -1 | cut -d ':' -f2`
            POSTER=`cat $RUTA/api_buscar.log | grep "poster_path" | head -1 | cut -d':' -f2 | tr -d '"' | cut -d'/' -f2 `
            POSTER_URL="http://image.tmdb.org/t/p/w500/${POSTER}"
            TOTAL_EPISODIOS=`curl -s --request GET --url "https://api.themoviedb.org/3/tv/$TMDBID/season/$TEMPORADA?language=es-ES&api_key=$TMDBKEY" --header 'content-type: application/json' --data '{}' | grep -o episode_number | wc -l`


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
            TORRENT=$(curl --silent --max-time 10 -L "https://descargas2020.com/descargar/serie-en-hd/$SERIE/temporada-$TEMPORADA/capitulo-$CAPITULO/#" | grep 'descargas2020.com/descargar-torrent' |  sed -e 's/^\s*//' -e '/^$/d' | cut -d'/' -f5 | sed 's/\/";//g' | tr -d [:space:])
            TORRENT_URL="https://descargas2020.com/descargar-torrent/${TORRENT}/${TORRENT}.torrent"


            #Si la variable TORRENT está a null (el enlace no se ha encontrado)
            if [ -z $TORRENT ]; then
                echo "Archivo no disponible o error: https://descargas2020.com/descargar/serie-en-hd/$SERIE/temporada-$TEMPORADA/capitulo-$CAPITULO/#"
                continue
            fi

            #Si el capítulo a descargar y el total coinciden, es el último de la temporada
            if [ $TOTAL_EPISODIOS = $CAPITULO ]; then
                EXTRA_INFO="Ultimo capitulo de la temporada $TEMPORADA"
            else
                EXTRA_INFO=""
            fi
 

            #Descargamos
            cd $RUTA/torrents/ 
            wget --timeout=15 --header='Host: descargas2020.com' --header='User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36' --header='Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8' --header='Accept-Language: es-ES,es;q=0.9,en;q=0.8' --header="Referer: https://descargas2020.com/descargar/serie-en-hd/$SERIE/temporada-$TEMPORADA/capitulo-$CAPITULO/" --header='Cookie: __PPU_SESSION_1_1549501_false=1550004812922|3|1550082642633|3|1; PHPSESSID=6f4f9jfd0du579e7vbin6iibe1' --header='Connection: keep-alive' $TORRENT_URL -c

            #Copiamos a 'autodescargas' del servidor del salón
            if /usr/bin/smbclient //192.168.1.112/autodescarga -U user%password -c "put ${TORRENT}.torrent"; then

                rm -f ${TORRENT}.torrent

                #Telegram OK. Comprobamos que exista la carátula, si no mandamos solo texto (para que el Telegram llegue bien)
                if [ -e $RUTA/poster/$POSTER ]; then

                    curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendPhoto -F chat_id=$TELEGRAMCHANNEL -F photo=@$RUTA/poster/`cut -d '/' -f2 <<< $POSTER` -F caption="Descargando *$(tr '[:lower:]' '[:upper:]' <<< $SERIE)* s${TEMPORADA}e${CAPITULO} - total: $TOTAL_EPISODIOS episodios. $EXTRA_INFO" -F parse_mode=markdown

                else

                    curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="Descargando *$(tr '[:lower:]' '[:upper:]' <<< $SERIE)* s${TEMPORADA}e${CAPITULO} - total: $TOTAL_EPISODIOS episodios"

                fi

            else
                #Telegram KO
                curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="⚠️  Error al copiar el torrent *$SERIE* s${TEMPORADA}e${CAPITULO} a la carpeta autodescarga"

            fi

 
       
            
        else
            echo "No hay coincidencia en $DESCARGA"
        fi

    done
done






#######################################
# COMPROBAMOS SERIES NUEVAS (S01E01)
#######################################


#Saca las nuevas series que han subido (temporada 1 capitulo 1), y envia notificación de las que tengan más de un 7 en IMDB
echo "Comprobando si hay alguna serie nueva..."

cat /tmp/descargas2020.feed | sed -n 's:.*<link>\(.*\)</link>.*:\1:p' | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep serie-en-hd | grep descargar | grep temporada-1 | grep capitulo-01 | cut -d '/' -f6 | while read SERIENUEVA
do
    echo "Comprobando $SERIENUEVA"
    
    #IMDB 
    IMDBID="$(curl -s https://www.imdb.com/find?q="$(tr '-' '+' <<< $SERIENUEVA)"\&s=tt | grep -o '/title/tt[0-9]*/?ref_=fn_tt_tt_1' | head -1)"
    PUNTUACION="$(curl -s https://www.imdb.com/$IMDBID | grep -o 'title="[0-9]*.[0-9]* based' | sed 's/title="//g' | cut -d' ' -f1 | tr '.' ',')"

    #Solo nos quedamos con las de más de un 7 (quitamos decimales)
    if [[ $( cut -d ',' -f1 <<< $PUNTUACION ) -ge 7 ]]; then

        RESUMEN=`curl -s https://www.imdb.com/$(curl -s https://www.imdb.com/find?q="$(tr '-' '+' <<< $SERIENUEVA)"\&s=tt | grep -o '/title/tt[0-9]*/?ref_=fn_tt_tt_1' | head -1) | grep -A1 'summary_text' | tail -n 1 | sed -e 's/^[ \t]*//' `

        #Traducimos a español
        if hash trans 2>/dev/null; then
            RESUMEN=`/usr/bin/trans :es -b "$RESUMEN"`
        fi

        curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="📺 Nueva serie: [$(tr '-' ' ' <<< $SERIENUEVA | tr '[:lower:]' '[:upper:]' )](https://www.imdb.com$IMDBID) - ${PUNTUACION}⭐ - $RESUMEN" -F parse_mode=markdown


    else

        echo "$PUNTUACION 💩"
    fi

done


#######################################
# COMPROBAMOS TEMPORADAS NUEVAS (S*E01)
#######################################


#Saca las nuevas series que han subido (capitulo 1 de cualquier temporada), y envia notificación por si se nos ha pasado una de las nuestras
echo "Comprobando si hay alguna temporada nueva de cualquier serie..."

cat /tmp/descargas2020.feed | sed -n 's:.*<link>\(.*\)</link>.*:\1:p' | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep serie-en-hd | grep descargar | grep capitulo-01 | cut -d '/' -f6,7,8 | while read TEMPORADANUEVA
do
    SERIE="$(cut -d '/' -f1 <<< $TEMPORADANUEVA)"
    TEMPORADA="$(cut -d '/' -f2 <<< $TEMPORADANUEVA | cut -d '-' -f2- )"
    CAPITULO="$(cut -d '/' -f3 <<< $TEMPORADANUEVA | cut -d '-' -f2- )"

    echo "Encontrada temporada $TEMPORADA, capitulo $CAPITULO de $SERIE"

    #Si la temporada es la 1, ya ha actuado la función anterior, así que saltamos
    if ! [ $TEMPORADA = 1 ]; then

        curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="📺 Nueva temporada (*$TEMPORADA*) de *$(tr '-' ' ' <<< $SERIE | tr '[:lower:]' '[:upper:]' )*" -F parse_mode=markdown
    
    fi

done







#######################################
# COMPROBAMOS LAS PELICULAS
#######################################

#Saca las nuevas peliculas en MicroHD, y envia notificación de las que tengan más de un 7 en IMDB
echo "Comprobando peliculas..."

cat /tmp/descargas2020.feed | sed -n 's:.*<link>\(.*\)</link>.*:\1:p' | sed "/$(cat $RUTA/ultimo.feed)/Q" | grep "cine-alta-definicion-hd" | grep microhd | cut -d '/' -f6 | while read PELICULA
do
    echo "Comprobando $PELICULA"
   
    #IMDB 
    IMDBID="$(curl -s https://www.imdb.com/find?q="$(tr '-' '+' <<< $PELICULA)"\&s=tt | grep -o '/title/tt[0-9]*/?ref_=fn_tt_tt_1' | head -1)"
    PUNTUACION="$(curl -s https://www.imdb.com/$IMDBID | grep -o 'title="[0-9]*.[0-9]* based' | sed 's/title="//g' | cut -d' ' -f1 | tr '.' ',')"

    #Solo nos quedamos con las de más de un 7
    if [[ $( cut -d ',' -f1 <<< $PUNTUACION ) -ge 7 ]]; then

        #Entramos en la página de la descarga del capítulo y obtenemos el nombre del torrent, quitando espacios y texto que sobra
        TORRENT=$(curl --silent --max-time 10 -L "https://descargas2020.com/descargar/cine-alta-definicion-hd/$PELICULA/bluray-microhd/#" | grep 'descargas2020.com/descargar-torrent' |  sed -e 's/^\s*//' -e '/^$/d' | cut -d'/' -f5 | sed 's/\/";//g' | tr -d [:space:])
        TORRENT_URL="https://descargas2020.com/descargar-torrent/${TORRENT}/${TORRENT}.torrent"

        RESUMEN=`curl -s https://www.imdb.com/$(curl -s https://www.imdb.com/find?q="$(tr '-' '+' <<< $PELICULA)"\&s=tt | grep -o '/title/tt[0-9]*/?ref_=fn_tt_tt_1' | head -1) | grep -A1 'summary_text' | tail -n 1 | sed -e 's/^[ \t]*//' `

        #Traducimos a español
        if hash trans 2>/dev/null; then
            RESUMEN=`/usr/bin/trans :es -b "$RESUMEN"`
        fi

        ANNO=`curl -s https://www.imdb.com/$(curl -s https://www.imdb.com/find?q="$PELICULA"\&s=tt | grep -o '/title/tt[0-9]*/?ref_=fn_tt_tt_1' | head -1) | grep '<title>' | sed 's/<\/*title>//g' | sed 's/ - IMDb//' | sed 's/  //g' | rev | cut -d' ' -f1 | rev | head -1 | tr -d '(' | tr -d ')' `
        curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="🍿 Nuevo estreno en HD: [$(tr '-' ' ' <<< $PELICULA | tr '[:lower:]' '[:upper:]' )](https://www.imdb.com$IMDBID) 🔗[torrent]($TORRENT_URL) ($ANNO) - ${PUNTUACION}⭐" -F parse_mode=markdown


    else

        echo "$PUNTUACION 💩 - No hacemos nada"
    fi

done



#######################################
# ESTRENOS DE NETFLIX
#######################################

#Saca un listado de estrenos de Netflix, que tengan más de un 8.0 e IMDB ordenado por fecha de publicación

#Puntuación mínimo de IMDB
IMDBRATING=8.0

echo "Comprobando estrenos de Netflix"

#Comprobamos la herramienta recode, necesaria para pasar de HTML a ASCII el resultado de Netflix
if hash recode 2>/dev/null; then
    curl -s "https://reelgood.com/source/netflix?filter-imdb_start=$IMDBRATING&filter-sort=3" | sed 's/>/>\n/g' | grep '<td class="cd">' -A2 --no-group-separator | grep -v '<a href="'  | grep -v '<td class="cd">' | cut -d '<' -f1 | recode html..ascii | sed "/$(cat $RUTA/ultimo.netflix)/Q" | while read NETFLIX
    do

        if ! [ -z $NETFLIX ]; then    
            IMDBID="$(curl -s https://www.imdb.com/find?q="$(tr ' ' '+' <<< $NETFLIX | tr -d '&' | tr -d ':')"\&s=tt | grep -o '/title/tt[0-9]*/?ref_=fn_tt_tt_1' | head -1)"
            PUNTUACION="$(curl -s https://www.imdb.com/$IMDBID | grep -o 'title="[0-9]*.[0-9]* based' | sed 's/title="//g' | cut -d' ' -f1 | tr '.' ',')"
            echo "$NETFLIX - $PUNTUACION"

            
            curl -s -X POST https://api.telegram.org/${TELEGRAMAPIKEY}/sendMessage -F chat_id=$TELEGRAMCHANNEL -F text="📣 Nuevo en NETFLIX: [$(tr '-' ' ' <<< $NETFLIX | tr '[:lower:]' '[:upper:]' )](https://www.imdb.com$IMDBID) - ${PUNTUACION}⭐" -F parse_mode=markdown
        fi
    done

    #Guardamo la primera entrada de Netflix para cortar ahí la próxima vez, escapando las barras para el siguiente sed
    curl -s "https://reelgood.com/source/netflix?filter-imdb_start=$IMDBRATING&filter-sort=3" | sed 's/>/>\n/g' | grep '<td class="cd">' -A2 --no-group-separator | grep -v '<a href="'  | grep -v '<td class="cd">' | head -1 | cut -d '<' -f1 | sed 's/\//\\\//g' | recode html..ascii > $RUTA/ultimo.netflix

else
    echo "Herremienta recode no encontrada, saltamos la verificación de Netflix"
fi



#Guardamo la primera entrada de descargas2020.com para cortar ahí la próxima vez, escapando las barras para el siguiente sed
cat /tmp/descargas2020.feed | sed -n 's:.*<link>\(.*\)</link>.*:\1:p' | grep descargar | head -n 1 | sed 's/\//\\\//g' > $RUTA/ultimo.feed
