#!/bin/bash

#Pasándole una serie y temporada, devuelve en CSV nombre completo,número de capítulos, url_poster, nombre_poster

SERIE=$1
TEMPORADA=$2

APIKEY="1234567890ABCDEFGHIJKLMNO"
POSTER_SIZE=500     #Valores: 92, 54, 185, 342, 500, 780
POSTER_URL_BASE="http://image.tmdb.org/t/p/w$POSTER_SIZE/"

#obtener ID de la serie:
#Si el nombre puede devolver más de un resultado, ampliar los términos separando con %20. Pero por si acaso dejo solo el primer resultado
curl -s --request GET --url "https://api.themoviedb.org/3/search/tv?query=$SERIE&season_number=$TEMPORADA&language=es-ES&api_key=$APIKEY" --header 'content-type: application/json' --data '{}' | tr ',' "\n" > /opt/smartmirrorPI/descargas2020/api_buscar.log

ID=`cat /opt/smartmirrorPI/descargas2020/api_buscar.log | grep '"id":' | head -1 | cut -d ':' -f2`
NOMBRE=`cat /opt/smartmirrorPI/descargas2020/api_buscar.log | grep '"name":' | head -1 | cut -d ':' -f2 | tr -d '(' | tr -d ')' | tr [:space:] '_' `
POSTER=`cat /opt/smartmirrorPI/descargas2020/api_buscar.log | grep "poster_path" | head -1 | cut -d':' -f2 | tr -d '"' | cut -d'/' -f2  | tr -d '}' | tr -d ']'`

#número de episodios
EPISODIOS=`curl -s --request GET --url "https://api.themoviedb.org/3/tv/$ID/season/$2?language=es-ES&api_key=$APIKEY" --header 'content-type: application/json' --data '{}' | grep -o episode_number | wc -l`


echo "$NOMBRE $EPISODIOS ${POSTER_URL_BASE}${POSTER} ${POSTER}"
