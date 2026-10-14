# Grzybowa mapa – plan aplikacji mobilnej

Oct 6, 2026 · @Michał

## 1. Cel i założenia

Aplikacja pokazuje na mapie lasu, gdzie i z jakim potencjałem warto dziś szukać konkretnych gatunków grzybów, i tłumaczy każdą ocenę regułami, nie modelem językowym. Całość liczy się na telefonie, bez serwera, bez logowania, dla jednego użytkownika.

**Co apka robi**

- Rysuje mapę (OSM/MapLibre) z pozycją GPS użytkownika i warstwą lasu.
- Nakłada siatkę potencjału (np. 100 × 100 m) dla wybranego gatunku lub „dowolnego jadalnego”.
- Po tapnięciu w pole pokazuje listę gatunków z oceną 0–100 i uzasadnieniem w punktach („sosna 80-letnia na piasku, 38 mm deszczu 9–14 dni temu, sezon szczytowy”).
- Pozwala dodać obserwację (gatunek, ilość, miejsce, data, opcjonalnie zdjęcie) i uczy się z niej lokalnie.

**Czego apka NIE robi (świadomie)**

- Nie identyfikuje grzybów ze zdjęcia i nie orzeka o jadalności. Na ekranie startowym jedno zdanie: „Apka podpowiada, gdzie szukać. Co zebrałeś, sprawdzasz sam.”
- Nie używa LLM ani sieci neuronowej do oceny. Silnik to jawne reguły + proste statystyki aktualizowane obserwacjami.
- Nie ma backendu, kont, synchronizacji. Dane użytkownika leżą w SQLite na telefonie; eksport/import to plik JSON.
- Nie pokazuje „prawdopodobieństwa” w sensie skalibrowanym. Pokazuje **indeks potencjału 0–100** w czterech pasmach (niski / umiarkowany / dobry / bardzo dobry). Słowo „prawdopodobieństwo” w UI nie występuje, bo nie mamy danych, żeby je skalibrować.

**Założenia techniczne**

- Internet potrzebny tylko do pobrania kafelków mapy, warstw lasu dla wybranego regionu i pogody. Po pobraniu regionu wszystko działa offline (w lesie zasięg bywa słaby).
- Jeden region roboczy = prostokąt do ok. 30 × 30 km wybrany przez użytkownika; można mieć kilka.
- Czas obliczenia siatki dla regionu po zmianie pogody: poniżej 2 s na średnim telefonie.

## 2. Uczciwa ocena wykonalności

Pomysł jest wykonalny i dane publiczne są lepsze, niż zakłada brief – ale jedno założenie trzeba zmienić, a jedno ryzyko trzeba nazwać wprost.

**Zmień źródło gleb: nie geoportal, tylko Bank Danych o Lasach.** Mapa glebowo-rolnicza w geoportalu opisuje głównie grunty rolne; w lesie ma dziury albo ogólniki. Tymczasem BDL udostępnia przez ArcGIS REST warstwę „Siedliska leśne” z polami `site_type_cd` (typ siedliskowy lasu: Bśw, BMśw, LMśw, Lśw…), `soil_subtype_cd` (podtyp gleby), `moisture_cd` (wilgotność), `geol_depos` (utwór geologiczny) i `soil_species` (gatunek gleby), a obok warstwę „Drzewostany” z `species_cd`, `species_age`, `part_cd` (udział gatunku) i `storey_cd` (piętro) – z geometrią w GeoJSON, bez klucza API. To jest dokładnie to, czego potrzebuje silnik: dla grzybów mykoryzowych partner drzewny i wiek drzewostanu są ważniejsze niż pH gleby, a siedlisko leśne koduje glebę i wilgotność razem. Geoportal zostaje tylko jako źródło rzeźby terenu (NMT) i ewentualnie ortofotomapy.

**Co jest mocne**

- Pogoda: Open-Meteo daje za darmo (użytek niekomercyjny, bez klucza) prognozę 16 dni, historię od 1940 i – kluczowe – wilgotność i temperaturę gleby na kilku głębokościach. Jedno zapytanie na region na dzień wystarczy.
- Lasy Państwowe to ok. 75–80 % lasów w Polsce i mają pełne dane. Lasy prywatne są w BDL częściowo („wg PUL”), tam oceny będą słabsze; apka ma to pokazywać jako „brak danych o drzewostanie”, nie udawać.
- Mapa: MapLibre GL + kafelki OpenFreeMap albo własny plik PMTiles regionu. Działa offline, licencja ODbL, zero kosztów.

**Ryzyka, których nie da się zaprogramować**

- Brak danych walidacyjnych. Nie ma publicznego zbioru „tu i wtedy były borowiki” o jakości pozwalającej skalibrować model. Pierwsza wersja heurystyki będzie oparta na wiedzy atlasowej i doświadczeniu grzybiarzy, czyli będzie *wiarygodna co do kierunku, niepewna co do skali*. Stąd „indeks potencjału”, nie „prawdopodobieństwo”.
- Pogoda w skali 100 m nie istnieje. Open-Meteo ma siatkę ok. 1–11 km; różnice między sąsiednimi polami siatki będą pochodzić tylko z siedliska, drzewostanu i rzeźby, nie z pogody. To jest OK, ale agent ma o tym wiedzieć, żeby nie liczyć pogody per komórka.
- Wiek danych BDL: opisy taksacyjne są aktualizowane co 10 lat (pole `a_year`). Zrąb sprzed 3 lat może w danych nadal być 90-letnią sośniną. Rozwiązanie: pokazywać rok danych w uzasadnieniu i pozwolić użytkownikowi oznaczyć pole jako „wycięte”.
- Zasięg w lesie. Wszystko, co potrzebne do oceny, musi być ściągnięte wcześniej dla regionu; UI nie może blokować się na sieci.

**Co w briefie jest słuszne i zostaje**

- Reguły zamiast LLM: tak. Problem jest mały (kilkanaście gatunków, kilka zmiennych), wyjaśnialność jest wymaganiem, a LLM dodałby koszt i niedeterminizm.
- Uczenie z własnych obserwacji: tak, i to jest realna przewaga nad każdą publiczną apką. Grzybnia jest trwała – miejsce, gdzie rosły borowiki w 2026, da je w 2027 przy podobnej pogodzie. Osobista pamięć miejsc + poprawna pogoda to 80 % wartości.

## 3. Źródła danych

Cztery źródła wystarczą: BDL (las + gleba), Open-Meteo (pogoda), NMT z geoportalu (rzeźba) i kafelki OSM (podkład). Wszystko bez kluczy API i bez opłat przy użytku prywatnym.

| Dane | Źródło i endpoint | Co pobierać | Format / jak | Odświeżanie |
| --- | --- | --- | --- | --- |
| Drzewostany (gatunek, wiek, udział, piętro) | [BDL ArcGIS REST, Mapa\_drzewostanow, warstwa 66 „Drzewostany PGL LP”](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_drzewostanow/MapServer/66) (+ warstwa 67 dla lasów poza LP) | `species_cd`, `species_age`, `part_cd`, `storey_cd`, `stand_struct_cd`, `a_year`, geometria | `…/66/query?geometry=<bbox>&geometryType=esriGeometryEnvelope&inSR=4326&outSR=4326&outFields=*&f=geojson`; max 2000 rekordów na zapytanie → stronicować `resultOffset`; dane w EPSG:2180, prosić o `outSR=4326` | Raz na region, ręcznie „odśwież region” |
| Siedlisko i gleba leśna | [BDL ArcGIS REST, Mapa\_siedlisk, warstwa 20 „Siedliska leśne”](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_siedlisk/MapServer/20) | `site_type_cd` (TSL), `soil_subtype_cd`, `moisture_cd`, `geol_depos`, `soil_species`, `arable_formerly` (porolny!), `a_year` | jak wyżej, `f=geojson`, stronicowanie | Raz na region |
| Utwory geologiczne (zapas, gdy brak siedliska) | Mapa\_drzewostanow, warstwa 69 „Powierzchniowe utwory geologiczne” | typ utworu (piaski, gliny, torfy) | jak wyżej | Raz na region |
| Podkład WMS/WMTS do podglądu lasu | [Usługi OGC BDL](https://www9.bdl.lasy.gov.pl/portal/uslugi-mapowe-ogc) – `WMTS_BDL` | kafelki rastrowe oddziałów i wydzieleń | WMTS, EPSG:3857 | Cache kafelków |
| Pogoda bieżąca + 16 dni prognozy + ostatnie 92 dni | Open-Meteo Forecast API `https://api.open-meteo.com/v1/forecast` z `past_days=92` | godzinowo: `precipitation`, `temperature_2m`, `relative_humidity_2m`, `soil_temperature_0_to_7cm`, `soil_temperature_7_to_28cm`, `soil_moisture_0_to_7cm`, `soil_moisture_7_to_28cm`; dziennie: `precipitation_sum`, `temperature_2m_min/max`, `et0_fao_evapotranspiration` | JSON, 1 zapytanie na region (centroid) lub na punkt siatki 10 km dla regionów >20 km | Raz dziennie przy otwarciu apki online |
| Historia pogody (do analizy własnych obserwacji wstecz) | Open-Meteo Archive API `https://archive-api.open-meteo.com/v1/archive` | te same zmienne, zakres dat | JSON | Na żądanie, przy imporcie starych obserwacji |
| Rzeźba terenu (NMT) | Geoportal GUGiK – NMT (usługa WCS lub pobranie arkuszy ASCII/GeoTIFF dla regionu) | wysokość → nachylenie, ekspozycja, TWI (wskaźnik wilgotności topograficznej) | GeoTIFF w EPSG:2180, próbkować do siatki 25–50 m | Raz na region |
| Podkład mapy | OpenFreeMap (kafelki wektorowe OSM, bez klucza) albo wycięty plik PMTiles regionu | styl „outdoor”: lasy, drogi leśne, cieki, szlaki | MapLibre GL Native (Flutter/RN) | Cache + pobranie offline regionu |
| Granice lasu poza LP (gdy BDL puste) | OSM: `landuse=forest`, `natural=wood`, `leaf_type` (z tych samych kafelków) | przybliżony typ: iglasty / liściasty / mieszany | atrybuty z kafelków wektorowych | z podkładem |

**Uwagi dla agenta**

- Zanim zacznie kodować, ma odpalić jedno zapytanie testowe na warstwę 66 i 20 dla bboxa \~5 × 5 km i zapisać przykładowy GeoJSON do repo jako fixture. Słowniki kodów (`species_cd`: SO, ŚW, JD, BK, DB, BRZ, OL, GB, MD, OS, TP…; `site_type_cd`; `moisture_cd`) spisać z odpowiedzi i trzymać w `knowledge/codes.json`.
- Zapytania ArcGIS REST mają limit skali w metadanych (`Min Scale 75000`) – dotyczy tylko rysowania, nie `query`. Jeśli serwer odrzuci duży bbox, dzielić region na kafle 5 km.
- Open-Meteo: zapisywać surową odpowiedź w SQLite z datą; silnik liczy wskaźniki z zapisu, nie z sieci. Nazwy zmiennych agent ma zweryfikować w aktualnej dokumentacji, bo lista się zmienia.
- Dostęp do NMT w geoportalu bywa przez WCS z ograniczeniem rozmiaru; prostsza droga: raz pobrać arkusze dla regionu i trzymać lokalnie. Jeśli to blokuje MVP, rzeźbę pominąć w fazie 1 (waga 0) i dodać w fazie 3.
- Licencje: dane BDL i geoportalu są otwarte do użytku; OSM – ODbL (podać atrybucję na mapie); Open-Meteo – CC BY 4.0, niekomercyjnie bez klucza.

Źródła sprawdzone 6 października 2026: [opis warstwy 66 BDL](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_drzewostanow/MapServer/66), [opis warstwy 20 BDL](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_siedlisk/MapServer/20), [lista usług OGC BDL](https://www9.bdl.lasy.gov.pl/portal/uslugi-mapowe-ogc), [Open-Meteo – funkcje](https://open-meteo.com/en/features).

## 4. Architektura

Jedna aplikacja Flutter, offline-first, z czterema modułami: pobieranie regionu, silnik regułowy, profil użytkownika i UI mapy. Żadnej logiki poza telefonem.

**Stack (decyzja)**

- Flutter (Dart) – jeden kod na Android i iOS, dobra wydajność pętli po siatce, dojrzałe `sqflite`/`drift`. Alternatywa React Native + Expo jest OK, jeśli agent zna ją lepiej; wtedy MapLibre przez `@maplibre/maplibre-react-native`, a silnik w czystym TypeScript.
- Mapa: `maplibre_gl` (MapLibre GL Native). Podkład: styl wektorowy z OpenFreeMap albo lokalny PMTiles. Siatka potencjału jako warstwa GeoJSON `fill` z kolorem z wartości `score` (4 pasma), rysowana tylko w aktualnym bbox.
- Dane: SQLite przez `drift` (migracje, typowane zapytania). Duże geometrie (wydzielenia, NMT) jako pliki w katalogu aplikacji, w SQLite tylko indeks przestrzenny (bbox per wydzielenie) i atrybuty.
- Silnik: czysty Dart, bez zależności od UI, w osobnym pakiecie `engine/` z testami jednostkowymi. Musi dać się uruchomić z CLI na zrzucie danych regionu (ważne dla debugowania heurystyki).
- GPS: `geolocator`. Zdjęcia: `image_picker`, zapis lokalny, bez uploadu.

&#91;embedded content: architektura · 4 źródła, cache, silnik z bazą wiedzy i profilem, UI\]

Strzałki w dół to przepływ danych przy liczeniu; jedyna strzałka w górę to obserwacja użytkownika, która zmienia profil, a przez niego kolejne oceny.

**Przepływ przy pierwszym użyciu regionu**

1. Użytkownik zaznacza prostokąt (max \~30 × 30 km) i nazywa region.
2. `RegionLoader` dzieli bbox na kafle 5 km, pobiera z BDL warstwy 66/67 (drzewostany) i 20 (siedliska) jako GeoJSON, stronicując po 2000 rekordów; zapisuje do plików i buduje indeks bbox w SQLite.
3. Pobiera NMT dla bboxa (faza 3) i liczy nachylenie, ekspozycję, TWI do rastra 25 m.
4. Pobiera kafelki mapy dla zoomów 10–16 do cache.
5. `GridBuilder` buduje siatkę 100 m (EPSG:3857, przycięta do granic lasu) i dla każdej komórki wylicza **statyczne cechy**: dominujący gatunek drzewa i udziały (z `part_cd`), wiek, TSL, podtyp gleby, wilgotność, porolność, nachylenie, ekspozycja, TWI, odległość do skraju lasu, odległość do drogi/ścieżki. Zapis do tabeli `grid_cells`. To liczy się raz; 30 × 30 km = 90 000 komórek, zajmuje sekundy.

**Przepływ codzienny**

1. Przy starcie online: jedno zapytanie Open-Meteo dla centroidu regionu (dla regionów > 20 km: 4 punkty i interpolacja), zapis surowy do `weather_days`.
2. `WeatherIndex` liczy z zapisu wskaźniki dynamiczne na dziś i na +7 dni (patrz sekcja 6).
3. `Scorer` dla każdej komórki i każdego gatunku z filtra: score = f(cechy statyczne, wskaźniki pogodowe, dzień roku, prior użytkownika). Wynik do pamięci (nie do bazy), rysowany na mapie.
4. Tap w komórkę → `Explainer` zwraca listę czynników z wkładem i tekstem po polsku.

**Granice modułów (dla agenta)**

- `data/` – klienci BDL, Open-Meteo, NMT, kafelki; parsery; cache. Zero logiki grzybowej.
- `engine/` – `grid_builder`, `weather_index`, `scorer`, `explainer`, `personalization`. Zero zależności od Fluttera. Wejście i wyjście to zwykłe obiekty Dart, testowalne.
- `knowledge/` – `species.json`, `codes.json` (słowniki BDL), `tsl_profiles.json`. Dane, nie kod.
- `ui/` – ekrany, mapa, formularze.
- `storage/` – schemat `drift`, migracje, eksport/import JSON.

## 5. Baza wiedzy o grzybach

Baza to plik `knowledge/species.json`: jeden rekord na gatunek, z partnerami drzewnymi, siedliskami, oknem sezonu i wymaganiami pogodowymi. Wartości startowe poniżej są **wiedzą atlasową dla Polski, przybliżoną** – agent ma je wpisać jako punkt wyjścia, a użytkownik może je edytować w apce.

**Schemat rekordu**

```json
{
  "id": "boletus_edulis",
  "name_pl": "Borowik szlachetny",
  "name_lat": "Boletus edulis",
  "edible": true,
  "ecology": "mycorrhizal",
  "hosts": { "SO": 1.0, "ŚW": 0.9, "DB": 0.8, "BK": 0.8, "BRZ": 0.4, "JD": 0.5 },
  "stand_age": { "min": 25, "opt_lo": 50, "opt_hi": 120, "max": 200 },
  "tsl": { "Bśw": 1.0, "BMśw": 1.0, "LMśw": 0.8, "Lśw": 0.5, "Bw": 0.5, "BMw": 0.6, "Bb": 0.1, "Ol": 0.0 },
  "moisture_pref": "fresh",
  "arable_formerly_penalty": 0.3,
  "season": { "start_doy": 170, "peak_lo_doy": 240, "peak_hi_doy": 290, "end_doy": 320 },
  "weather": {
    "rain_window_days": [7, 21], "rain_min_mm": 25, "rain_opt_mm": 50,
    "lag_days": [8, 14],
    "soil_temp_c": { "min": 8, "opt_lo": 12, "opt_hi": 20, "max": 24 },
    "frost_kill_c": -2, "frost_recovery_days": 10,
    "dry_days_penalty_after": 5
  },
  "terrain": { "edge_bonus": 0.1, "twi_pref": "mid" },
  "explain": {
    "host_ok": "Pod {host} ({age} lat) – dobry partner mykoryzowy",
    "rain_ok": "{rain} mm deszczu {lag} dni temu – w sam raz",
    "season_peak": "Szczyt sezonu"
  }
}
```

Wartości `hosts` i `tsl` to mnożniki 0–1 (1 = idealnie). Brak klucza = 0. Pola `explain` to szablony po polsku z podstawieniami.

**Lista startowa (15 gatunków)**

| Gatunek | Główni partnerzy / podłoże | Siedliska (TSL) | Sezon (szczyt) | Deszcz → owocniki | Uwagi do reguł |
| --- | --- | --- | --- | --- | --- |
| Borowik szlachetny (*Boletus edulis*) | SO, ŚW, DB, BK; drzewostan 50–120 lat | Bśw, BMśw, LMśw | VI–XI (IX–X) | ≥25 mm w 7–21 dni, lag 8–14 d | Lubi skraje, prześwietlenia, mchy; kara za porolne i za Ol/Lł |
| Podgrzybek brunatny (*Imleria badia*) | SO, ŚW; 30–100 lat | Bśw, BMśw, BMw | VII–XI (IX–X) | ≥20 mm, lag 7–12 d | Toleruje gęstsze sośniny; mocny po ciepłym deszczu |
| Koźlarz babka (*Leccinum scabrum*) | BRZ obowiązkowo (udział ≥20 %) | BMśw, BMw, LMw, Bw | VI–X (VIII–IX) | ≥20 mm, lag 7–10 d | Brzoza = warunek konieczny; wilgotniejsze siedliska premiowane |
| Koźlarz czerwony (*Leccinum aurantiacum*) | OS, TP (osika, topola) | LMśw, Lśw, Lw | VI–X (VIII–IX) | ≥20 mm, lag 7–10 d | Osika = warunek konieczny |
| Maślak zwyczajny (*Suillus luteus*) | SO wyłącznie; 10–40 lat | Bśw, Bs, BMśw | VII–XI (IX–X) | ≥15 mm, lag 5–8 d | Młodniki i skraje sosnowe, trawiaste; reaguje szybko |
| Maślak sitarz (*Suillus bovinus*) | SO; 15–60 lat | Bśw, Bs, Bw | VII–XI (IX–X) | ≥15 mm, lag 5–8 d | Piaski, bory suche; towarzyszy maślakowi |
| Pieprznik jadalny / kurka (*Cantharellus cibarius*) | SO, ŚW, BK, DB; 30–90 lat | Bśw, BMśw, LMśw | VI–X (VII–IX) | ≥30 mm skumulowane w 14–28 dni, lag 10–20 d | Wolno reaguje, długo trwa; mchy, lekkie nachylenie; kara za suszę >10 dni mniejsza niż u borowika |
| Rydz / mleczaj rydz (*Lactarius deliciosus*) | SO; 10–50 lat | Bśw, BMśw, Bs | VIII–XI (IX–X) | ≥20 mm, lag 7–12 d | Młode sośniny, trawiaste skraje, przydroża |
| Opieńka miodowa (*Armillaria* s.l.) | saprotrof/pasożyt: pniaki, martwe drewno; ŚW, SO, DB, BK | wszystkie poza Bs | IX–XI (X) | ≥20 mm, lag 7–14 d; **wymaga nocy <10 °C** | Reguła temperaturowa ważniejsza od deszczu; zręby i drzewostany po cięciach (`stand_struct_cd`, KO/KDO) premiowane |
| Czubajka kania (*Macrolepiota procera*) | saprotrof: skraje, polany, trawy | Lśw, LMśw, skraj lasu | VII–X (VIII–IX) | ≥20 mm, lag 7–12 d | `edge_bonus` wysoki; dystans do skraju <100 m |
| Płachetka kołpakowata (*Cortinarius caperatus*) | SO, ŚW; borówka czarna | Bśw, BMśw, Bw, BMb | VIII–X (IX) | ≥20 mm, lag 7–12 d | Kwaśne, mszyste bory; lubi wilgotne obniżenia |
| Podgrzybek zajączek (*Xerocomellus subtomentosus*) | SO, ŚW, DB, BK | BMśw, LMśw, Lśw | VII–X (VIII–IX) | ≥20 mm, lag 7–12 d | Mało wymagający; dobry „gatunek tła” |
| Gołąbek (grupa jadalnych, *Russula* spp.) | BK, DB, SO, ŚW | LMśw, Lśw, BMśw | VII–X (VIII–IX) | ≥20 mm, lag 5–10 d | Oceniane jako grupa; UI ostrzega, że identyfikacja gatunku w grupie jest trudna |
| Smardz (*Morchella* spp.) | saprotrof: łęgi, JS, TP, OL; zręby, pożarzyska | Lł, Lw, OlJ | IV–V (IV/V) | ≥15 mm + gleba ≥8 °C | Jedyny gatunek wiosenny; pod ochroną częściową w lesie – zbiór dozwolony tylko na terenach ogrodów/parków, apka ma to wyświetlić |
| Borowik usiatkowany (*Boletus reticulatus*) | DB, BK; ciepłe lasy liściaste | Lśw, LMśw | V–IX (VI–VII) | ≥25 mm, lag 7–12 d | Wczesny borowik; ciepłe ekspozycje S/SW premiowane |

Kody gatunków drzew jak w BDL `species_cd`: SO sosna, ŚW świerk, JD jodła, MD modrzew, BK buk, DB dąb, GB grab, BRZ brzoza, OL olsza, OS osika, TP topola, JS jesion.

**Zasady utrzymania bazy**

- Każda liczba w `species.json` ma pole `source` („atlas”, „użytkownik”, „kalibracja”), żeby personalizacja nie nadpisywała wiedzy bazowej po cichu.
- Agent nie wymyśla gatunków ponad listę; dodanie gatunku = dodanie rekordu, bez zmian w kodzie silnika.
- Trujące sobowtóry (np. goryczak żółciowy przy borowiku, muchomor zielonawy przy gołąbkach i kani) nie są oceniane, ale w szczegółach gatunku jest sekcja „uważaj na” z tekstem i linkiem do atlasu. To nie zastępuje identyfikacji.

## 6. Silnik regułowy

Indeks komórki dla gatunku to iloczyn czynników 0–1 pomnożony przez 100, gdzie czynniki siedliskowe są bramkami (zero wyłącza), a pogodowe i sezonowe skalują. Iloczyn, nie suma: borowik nie urośnie w olsie, choćby pogoda była idealna.

```latex
S = 100 \cdot H \cdot A \cdot T \cdot P_{site} \cdot F_{season}(d) \cdot W_{rain} \cdot W_{temp} \cdot W_{frost} \cdot R_{terrain} \cdot U_{user}
```

| Czynnik | Z czego | Jak liczony | Zakres |
| --- | --- | --- | --- |
| H – partner drzewny | `species_cd`, `part_cd` komórki | suma po gatunkach drzew: udział × `hosts[gatunek]`; dla saprotrofów H = 1 | 0–1, bramka |
| A – wiek drzewostanu | `species_age` dominanta | trapez: 0 poniżej `min`, rośnie do `opt_lo`, 1 do `opt_hi`, spada do `max` | 0–1 |
| T – siedlisko | `site_type_cd` | `tsl[TSL]`; gdy brak siedliska w danych: z `geol_depos` (piaski→Bśw/BMśw, gliny→LMśw/Lśw, torf→Bb/Ol), waga 0.7 za niepewność | 0–1, bramka |
| P\_site – kary siedliskowe | `arable_formerly`, `moisture_cd`, `degradation_cd` | porolny: 1 − `arable_formerly_penalty`; wilgotność niezgodna z `moisture_pref`: 0.6 | 0.3–1 |
| F\_season – dzień roku | data | trapez po `start_doy`, `peak_lo`, `peak_hi`, `end_doy`; poza oknem 0.05 (nie 0, bo anomalie się zdarzają) | 0.05–1 |
| W\_rain – deszcz z opóźnieniem | `precipitation_sum` dzienny, ostatnie 30 dni | suma opadu w oknie \[dziś − lag\_hi − rain\_window, dziś − lag\_lo\]; przelicz: 0 przy 0 mm, 0.5 przy `rain_min_mm`, 1 przy `rain_opt_mm`, 1 powyżej; następnie kara za suszę: za każdy dzień bez ≥1 mm w ostatnich `dry_days_penalty_after` dniach −0.08 | 0–1 |
| W\_temp – temperatura gleby | `soil_temperature_7_to_28cm`, średnia 5-dniowa | trapez po `soil_temp_c`; dla opieńki dodatkowa reguła: min. 3 noce z T\_min < 10 °C w ostatnich 10 dniach, inaczej 0.3 | 0–1 |
| W\_frost – przymrozek | `temperature_2m_min` | jeśli T\_min ≤ `frost_kill_c` w ostatnich `frost_recovery_days`: 0.2, liniowo wraca do 1 | 0.2–1 |
| R\_terrain – rzeźba (faza 3) | nachylenie, ekspozycja, TWI, odległość do skraju | 1 + `edge_bonus` gdy skraj <100 m; TWI: `twi_pref` low/mid/high → 0.8–1.1; ekspozycja S/SW przy gatunkach ciepłolubnych +0.1; przycięte do \[0.7, 1.2\] | 0.7–1.2 |
| U\_user – prior użytkownika | obserwacje (sekcja 7) | lokalny mnożnik z jądra wokół znalezisk + kalibracja gatunkowa | 0.5–2.0 |

**Wskaźniki pogodowe – szczegóły implementacji**

- Wszystko liczy się z tabeli `weather_days` (dzienne agregaty z Open-Meteo), raz dziennie, dla całego regionu. Pogoda nie zależy od komórki; różnice między komórkami daje tylko siedlisko, drzewostan, rzeźba i prior.
- Prognoza na +7 dni: te same wzory, z opadem prognozowanym (pomnożonym przez 0.7, bo prognoza opadu jest niepewna). UI pokazuje suwak „dziś … +7 dni”.
- Zdarzenie „wysyp”: jeśli w oknie opadowym padło ≥ `rain_opt_mm` w ≤ 3 dni, a potem były ≥ 4 ciepłe dni (gleba ≥ `opt_lo`), dodaj flagę `flush_expected` z datą = koniec deszczu + `lag_lo` … + `lag_hi`. UI pokazuje to jako powiadomienie lokalne „Za 3–6 dni spodziewany wysyp borowików w regionie X”.

**Agregacja do widoku „dowolny jadalny”**

Score komórki w trybie „wszystkie” = max po gatunkach (nie suma), z podpisem, który gatunek wygrał. Suma faworyzowałaby komórki z wieloma słabymi gatunkami.

**Wyjaśnienia „dlaczego tutaj”**

`Explainer` zwraca listę `{factor, value, weight_in_score, text_pl}` posortowaną po wpływie, osobno dodatnie i ujemne. Przykład dla borowika, 9 października:

- ✓ Sosna 72 lata, 80 % udziału – dobry partner (H = 0.95, A = 1.0)
- ✓ Bór mieszany świeży – idealne siedlisko (T = 1.0)
- ✓ 41 mm deszczu 9–13 dni temu (W\_rain = 0.85)
- ✓ Gleba 13 °C (W\_temp = 0.9)
- ✓ Szczyt sezonu (F = 1.0)
- ✗ Ostatnie 4 dni bez opadu (−0.24 w W\_rain)
- ✗ Dane drzewostanu z 2017 r. – sprawdź, czy nie było cięć
- ★ 300 m od Twojego znaleziska z 28.09.2025 (U = 1.6)

Teksty składane są z szablonów `explain` w `species.json` i ze stałych w `knowledge/explain_pl.json`. Żadnego generowania tekstu poza podstawieniem zmiennych.

**Pasma wyświetlania**

0–20 niski (bez koloru), 21–45 umiarkowany (żółty), 46–70 dobry (pomarańczowy), 71–100 bardzo dobry (czerwony). Komórki poza lasem i z H = 0 nie są rysowane wcale.

**Wymagania testowe dla silnika**

- Testy jednostkowe trapezów i okien opadowych na wartościach brzegowych.
- Test „złoty”: zrzut regionu 5 × 5 km + 30 dni pogody syntetycznej → oczekiwane rankingi 10 komórek, zapisane w repo; każda zmiana heurystyki musi świadomie zaktualizować ten plik.
- Test determinizmu: dwa uruchomienia na tych samych danych dają identyczny wynik.

## 7. Personalizacja z obserwacji użytkownika

Obserwacje zmieniają wynik dwiema drogami: **lokalny prior** (pamięć miejsc, bo grzybnia jest trwała) i **kalibracja gatunku** (poprawki do reguł, gdy użytkownik systematycznie znajduje grzyby tam, gdzie model daje mało). Obie są jawne, odwracalne i widoczne w wyjaśnieniu jako osobne pozycje.

**Rodzaje obserwacji**

| Typ | Co użytkownik wpisuje | Jak liczy się w modelu |
| --- | --- | --- |
| Znalezisko | gatunek, ilość (1–3: pojedyncze / kilka / dużo), GPS, data, opcjonalne zdjęcie i notatka | dodatnie, waga = ilość |
| Pusto | gatunek(i) lub „nic”, GPS, data | ujemne, waga 1; ważne, bo bez negatywów prior tylko rośnie |
| Korekta terenu | „wycięte”, „podmokłe”, „młodnik”, „zaorane” na komórce lub wydzieleniu | nadpisuje cechy statyczne komórki (np. wiek → 0), ze znacznikiem `source=user` |
| Ocena podpowiedzi | kciuk w górę/dół na komórce po wizycie | skrócony zapis znalezisko/pusto dla gatunków z filtra |

**Lokalny prior U\_local**

Dla komórki c i gatunku s:

```latex
U_{local}(c,s) = \exp\Big( \sum_{o \in O_s} w_o \cdot k(d(c,o)) \cdot g(\Delta t_o) \Big),\quad k(d) = e^{-d^2/2\sigma^2},\ \sigma = 150\,\text{m}
```

- `w_o` = +0.3 / +0.5 / +0.8 dla ilości 1/2/3; −0.4 dla „pusto”.
- `g(Δt)` – wygaszanie w czasie: 1.0 w tym samym sezonie, 0.8 po roku, 0.6 po dwóch latach, 0.4 później. Grzybnia trwa latami, więc nie zeruje się nigdy; zręb użytkownik oznacza korektą terenu.
- Wynik przycięty do \[0.5, 2.0\]. Jedno „dużo borowików” 100 m obok daje ×1.6; trzy sezony potwierdzeń dają sufit ×2.0; dwa „pusto” w szczycie sezonu zbijają do ×0.6.
- Negatyw liczy się tylko, jeśli tego dnia model dawał dla komórki S ≥ 40 bez priora. „Pusto” przy S = 10 niczego nie uczy.

**Kalibracja gatunku U\_calib**

Co 10 obserwacji danego gatunku (lub na żądanie w ustawieniach) uruchamia się prosta procedura, nadal regułowa:

1. Dla każdej obserwacji policz, jaki był score bez priora i które czynniki były najniższe.
2. Jeśli w ≥60 % znalezisk ten sam czynnik był „wąskim gardłem” (np. T dla siedliska Lśw = 0.5, a użytkownik tam regularnie znajduje borowiki), podnieś ten jeden parametr w kopii użytkownika `species.user.json` o 0.1, max do 1.0; zapisz `source: "kalibracja"` i datę.
3. Analogicznie w dół: jeśli ≥60 % „pusto” przy S ≥ 40 ma wspólny czynnik, obniż go o 0.1, min 0.2.
4. Okno sezonu: jeśli znaleziska wypadają poza `[start_doy, end_doy]` trzy razy, rozszerz okno o 7 dni z tej strony.
5. Lag opadowy: dla znalezisk policz dni od ostatniego deszczu ≥10 mm; jeśli mediana różni się od środka `lag_days` o >3 dni, przesuń `lag_days` o 2 dni w tę stronę.

Zmiany są małe, pojedyncze i logowane w tabeli `calibration_log`, z przyciskiem „cofnij” i „przywróć atlas”. To celowo nie jest regresja ani uczenie maszynowe – użytkownik ma widzieć każdą zmianę reguły w czytelnym zdaniu: „Od 3.10.2026 podniesiono wagę siedliska Lśw dla borowika z 0.5 do 0.6 na podstawie 7 znalezisk”.

**Co personalizacja NIE robi**

- Nie zmienia bramek z 0 na >0 (nie „nauczy się”, że borowik rośnie w olsie bez partnerów drzewnych). Jeśli użytkownik tam znajduje, to prawie na pewno błąd danych o drzewostanie – apka sugeruje korektę terenu, nie zmianę biologii.
- Nie przenosi się między gatunkami ani regionami.
- Nie opuszcza telefonu. Eksport JSON na życzenie.

## 8. Ekrany i UX

Sześć ekranów, z mapą jako domem. Projekt dla jednej ręki w lesie: duże tapnięcia, wysoki kontrast, działa w rękawiczce i na słońcu, zero blokujących spinnerów sieciowych.

| Ekran | Co pokazuje | Akcje | Uwagi |
| --- | --- | --- | --- |
| **Mapa** (start) | Podkład OSM, kropka GPS z kierunkiem, siatka potencjału w 4 pasmach, kontury wydzieleń przy zoom ≥ 15, ikony własnych znalezisk | pasek u góry: wybór gatunku (chip „wszystkie” + chipy gatunków); suwak dnia „dziś … +7”; przycisk „centruj”; tap w komórkę → arkusz szczegółów; długie przytrzymanie → „dodaj obserwację tutaj” | Legenda pasm w rogu. Gdy region nie pobrany: baner „pobierz region, żeby zobaczyć potencjał”. Gdy pogoda starsza niż 36 h: ikona ostrzeżenia na suwaku |
| **Szczegóły komórki** (arkusz dolny) | Ranking gatunków z indeksem i pasmem; po rozwinięciu: lista „dlaczego” (✓ / ✗ / ★), dane źródłowe (drzewostan, wiek, TSL, rok danych), mini-wykres opadu ostatnich 21 dni | „Byłem: znalazłem / pusto”, „oznacz korektę terenu”, „nawiguj tutaj” (otwiera kompas/strzałkę w apce, nie Google Maps) | Arkusz nie zasłania pozycji użytkownika na mapie |
| **Dodaj obserwację** | Formularz: gatunek (ostatnio używane na górze), ilość 1/2/3, lokalizacja (GPS lub przesuń pinezkę), data (domyślnie teraz), zdjęcie, notatka; przełącznik „to było pusto” | Zapisz | Zapis działa offline; ≤ 3 tapnięcia dla typowego znaleziska |
| **Dziennik** | Lista obserwacji po dacie, filtr gatunek/region, podsumowanie sezonu (ile, gdzie, przy jakiej pogodzie) | edycja, usuwanie, eksport JSON/GPX | Kalendarz-heatmapa znalezisk po dniach roku – pomaga ocenić własne okno sezonu |
| **Regiony** | Lista pobranych regionów z rozmiarem, datą danych BDL, datą pogody | dodaj (rysuj prostokąt), odśwież dane BDL, odśwież pogodę, usuń | Pokazuje szacunkowy rozmiar przed pobraniem (MB) |
| **Gatunki i reguły** | Lista gatunków z bazy; karta gatunku: parametry, „uważaj na”, log kalibracji | włącz/wyłącz gatunek w filtrze, edytuj parametr, „przywróć atlas”, dodaj własny gatunek (formularz = schemat rekordu) | Edycja parametru pokazuje natychmiast wpływ na mapę (podgląd) |

**Zasady interfejsu**

- Słowa: „potencjał”, „warto sprawdzić”, nigdy „prawdopodobieństwo” ani „tu są grzyby”.
- Na ekranie startowym przy pierwszym uruchomieniu i w stopce karty gatunku: „Apka nie identyfikuje grzybów. Zbieraj tylko to, co znasz na pewno.”
- Mapa pamięta ostatni gatunek, zoom i dzień suwaka.
- Tryb terenowy (przełącznik): większe czcionki, jaśniejsze pasma, ukryte kontury wydzieleń, ekran nie gaśnie.
- Powiadomienie lokalne „spodziewany wysyp” tylko, jeśli użytkownik je włączy; max 1 dziennie.
- Brak sieci nie generuje błędów, tylko dyskretny stan „offline” i wiek danych.

**Czego nie ma w wersji 1**

Logowania, synchronizacji, udostępniania miejsc, rozpoznawania ze zdjęć, trybu społecznościowego, reklam.

## 9. Model danych i struktura plików

SQLite trzyma atrybuty, indeksy i wszystko, co użytkownik wpisał; ciężkie geometrie i rastry leżą jako pliki. Wynik scoringu nie jest zapisywany – liczy się na żądanie.

**Tabele SQLite (drift)**

| Tabela | Kluczowe kolumny | Uwagi |
| --- | --- | --- |
| `regions` | id, name, bbox (minx, miny, maxx, maxy), bdl\_fetched\_at, bdl\_data\_year\_min/max, weather\_fetched\_at, size\_bytes | jeden wiersz na region |
| `stands` | id (subarea\_id z BDL), region\_id, adress\_forest, bbox, dominant\_species\_cd, species\_age, a\_year, stand\_struct\_cd, geom\_file, geom\_offset | atrybuty dominanty + wskaźnik do geometrii w pliku GeoJSON; udziały wszystkich gatunków w `stand_species` |
| `stand_species` | stand\_id, species\_cd, part\_cd (udział 1–10), storey\_cd, species\_age | wiele wierszy na wydzielenie (piętra, domieszki) |
| `sites` | id (site\_type\_id), region\_id, bbox, site\_type\_cd, soil\_subtype\_cd, moisture\_cd, geol\_depos, soil\_species, arable\_formerly, a\_year, geom\_file, geom\_offset | siedliska z warstwy 20 |
| `grid_cells` | id, region\_id, col, row, lon, lat, stand\_id, site\_id, dominant\_species\_cd, species\_age, site\_type\_cd, moisture\_cd, arable\_formerly, slope\_deg, aspect\_deg, twi, dist\_edge\_m, dist\_road\_m, user\_override\_json | cechy statyczne; 90 000 wierszy na region 30 × 30 km; indeks (region\_id, col, row) |
| `weather_days` | region\_id, date, precip\_mm, tmin\_c, tmax\_c, soil\_t\_7\_28\_c, soil\_m\_7\_28, rh\_mean, is\_forecast | dzienne agregaty; forecast nadpisywany danymi rzeczywistymi, gdy nadejdą |
| `observations` | id, species\_id (null = „nic”), kind (found / empty / terrain\_fix / rating), amount 1–3, lon, lat, cell\_id, observed\_at, photo\_path, note, score\_at\_time, factors\_json | `score_at_time` i `factors_json` zapisane w momencie obserwacji – potrzebne do kalibracji |
| `species_user_overrides` | species\_id, json\_patch, source (user / calibration), changed\_at | nakładka na `species.json`; pusta = atlas |
| `calibration_log` | id, species\_id, parameter, old\_value, new\_value, reason\_text, observation\_ids, created\_at, reverted | każda zmiana reguły jako zdanie |
| `settings` | key, value | ostatni gatunek, zoom, tryb terenowy, powiadomienia |

**Pliki w katalogu aplikacji**

```
app_documents/
  regions/<region_id>/
    stands.geojsonl        # jedna geometria na linię, offsety w SQLite
    sites.geojsonl
    dem_25m.bin            # raster float32 (faza 3)
    tiles/                 # cache kafelków mapy (MBTiles lub PMTiles)
  photos/<observation_id>.jpg
  export/                 # eksporty JSON/GPX
```

**Struktura repo**

```
lib/
  data/        bdl_client.dart, open_meteo_client.dart, dem_client.dart, tile_cache.dart, region_loader.dart
  engine/      grid_builder.dart, weather_index.dart, scorer.dart, explainer.dart, personalization.dart, models.dart
  knowledge/   species.json, codes.json, tsl_profiles.json, explain_pl.json
  storage/     database.dart (drift), migrations/, export_import.dart
  ui/          map/, cell_details/, add_observation/, journal/, regions/, species/
test/
  engine/      trapezoid_test.dart, weather_index_test.dart, scorer_golden_test.dart, personalization_test.dart
  fixtures/    region_5km.geojson, weather_30d.json, expected_ranking.json
tool/
  score_cli.dart          # uruchamia silnik na fixture z linii poleceń
```

**Eksport / import**

Jeden plik `grzyby-export-<data>.json`: obserwacje, nadpisania gatunków, log kalibracji, lista regionów (bez danych BDL – te pobiera się ponownie). To jest też backup i droga na nowy telefon.

## 10. Plan wdrożenia w fazach

Silnik powstaje najpierw jako program konsolowy na zrzucie danych, a dopiero potem dostaje mapę – bo heurystykę trzeba móc testować bez klikania po telefonie. Szacunki czasu są orientacyjne, dla jednej osoby pracującej z agentem.

&#91;embedded content: roadmapa · 4 fazy, 4 bramki\]

Faza 0 jest bramą dla wszystkiego: jeśli zapytania do BDL nie działają tak, jak opisano w sekcji 3, trzeba to wiedzieć przed napisaniem UI.

**Kryteria akceptacji**

| Faza | Zrobione, gdy | Testy |
| --- | --- | --- |
| 0 – dane i silnik | `dart run tool/score_cli.dart --region fixtures/region_5km --date 2026-10-09 --species boletus_edulis` wypisuje 10 najlepszych komórek z uzasadnieniami; fixture BDL i pogody leżą w repo; `species.json` ma 15 gatunków | jednostkowe: trapezy, okna opadowe, bramki H/T; test złoty rankingu; determinizm |
| 1 – MVP mapa | Na telefonie: rysuję region, pobiera się w < 2 min dla 15 × 15 km, siatka rysuje się w < 2 s, tap pokazuje ranking i „dlaczego”, GPS działa offline po pobraniu | widget test arkusza szczegółów; test wydajności siatki (90 000 komórek × 15 gatunków < 2 s na średnim Androidzie); ręczny spacer |
| 2 – obserwacje | Dodanie znaleziska w ≤ 3 tapnięciach; po dodaniu „dużo” mapa wokół rośnie o pasmo; „pusto” obniża; eksport i import odtwarzają stan na drugim telefonie | test U\_local na syntetycznych obserwacjach (3 scenariusze); round-trip eksportu |
| 3 – rzeźba i kalibracja | NMT wczytany dla regionu, TWI widoczny w „dlaczego”; kalibracja po 10 obserwacjach tworzy wpis w logu i zmienia dokładnie jeden parametr; powiadomienie „wysyp” odpala się na danych testowych | test reguł kalibracji (podnieś / obniż / okno / lag) z oczekiwanym logiem; test flagi `flush_expected` |

**Kolejność wewnątrz fazy 1 (dla agenta)**

1. Pusty projekt Flutter z MapLibre i kropką GPS na kafelkach OpenFreeMap.
2. Ekran Regiony: rysowanie prostokąta, `RegionLoader` z BDL (bez NMT), pasek postępu, zapis do SQLite i plików.
3. `GridBuilder` i tabela `grid_cells`; podgląd siatki jednym kolorem (bez scoringu) – sprawdzenie, czy geometrie się zgadzają z podkładem.
4. Podłączenie silnika z fazy 0; pasma kolorów; chipy gatunków.
5. Open-Meteo i suwak dnia.
6. Arkusz szczegółów z `Explainer`.

**Co odłożyć, jeśli zabraknie czasu**

NMT i R\_terrain (waga 1.0 = neutralnie), powiadomienia, tryb terenowy, edycja parametrów w UI (na początek wystarczy edycja pliku). Nie odkładać: obserwacji negatywnych i `score_at_time` – bez nich kalibracja w fazie 3 nie ma danych.

## 11. Otwarte decyzje i instrukcje dla agenta

Trzy decyzje należą do właściciela projektu, reszta to lista rzeczy, które agent ma sprawdzić zanim napisze pierwszą linię UI.

**Do decyzji właściciela**

- [ ] Flutter czy React Native? Dokument zakłada Flutter; zmiana nie wpływa na architekturę, tylko na biblioteki.
- [ ] Pierwszy region testowy (bbox) – najlepiej las, który znasz i w którym masz historyczne znaleziska do wpisania jako obserwacje wsteczne.
- [ ] Czy w wersji 1 ma być edycja parametrów gatunków w UI, czy wystarczy edycja `species.json` w repo?

**Agent weryfikuje przed kodowaniem (faza 0, dzień 1)**

- [ ] Zapytanie `query` do warstwy 66 i 20 BDL z `f=geojson`, `outSR=4326`, bbox 5 × 5 km: czy działa, ile rekordów, czy `resultOffset` stronicuje, czy serwer wymaga `https`. Zapisać odpowiedzi jako fixture.
- [ ] Słowniki kodów z realnych danych: `species_cd`, `site_type_cd`, `moisture_cd`, `stand_struct_cd`, `storey_cd`, `part_cd` (skala udziału – sprawdzić, czy 1–10 czy procenty). Zapisać w `codes.json`.
- [ ] Czy warstwa 67 (lasy poza LP) ma te same pola co 66.
- [ ] Open-Meteo: aktualne nazwy zmiennych `soil_temperature_7_to_28cm`, `soil_moisture_7_to_28cm`, `et0_fao_evapotranspiration`; limit `past_days`; czy jedno zapytanie zwraca 92 dni wstecz + 16 prognozy.
- [ ] OpenFreeMap: aktualny adres stylu i warunki użycia; alternatywnie wygenerować PMTiles regionu (Protomaps) i trzymać lokalnie.
- [ ] Dostęp do NMT GUGiK dla bboxa (WCS lub pobranie arkuszy) – jeśli skomplikowane, zostawić na fazę 3 bez blokowania.
- [ ] Licencje bibliotek i atrybucje (OSM/ODbL, Open-Meteo CC BY, BDL) – tekst do ekranu „O aplikacji”.

**Zasady pracy agenta**

- Silnik w `engine/` nie importuje nic z Fluttera i jest testowany przed UI.
- Każda liczba w heurystyce pochodzi z `knowledge/*.json`, nigdy z kodu. Jeśli agent chce „poprawić” wartość atlasową, zmienia JSON i opisuje dlaczego w commicie.
- Żadnego wywołania LLM ani zewnętrznego API poza czterema źródłami z sekcji 3. Żadnej telemetrii.
- Teksty w UI po polsku, w `explain_pl.json` i plikach l10n; brak tekstów na sztywno w widgetach.
- Przy wątpliwości co do biologii gatunku: nie zgadywać, zostawić parametr z `source: "todo"` i wypisać na liście pytań do właściciela.
- Każda faza kończy się krótkim README: jak uruchomić, co działa, co nie, co trzeba zweryfikować w terenie.

**Pytania, na które odpowie dopiero sezon**

Czy `lag_days` dla borowika to 8–14 dni, czy raczej 5–10 w ciepłym wrześniu; czy TWI realnie różnicuje w płaskich borach Mazowsza; czy kara za porolność nie jest za ostra (porolne sośniny bywają maślakowe). To wszystko ma się wyjaśnić z obserwacji, nie z dyskusji – stąd priorytet dla zapisu `score_at_time` i negatywów.

**Źródła**

- [BDL – Drzewostany PGL LP, warstwa 66 (pola i endpoint query)](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_drzewostanow/MapServer/66)
- [BDL – Siedliska leśne, warstwa 20](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_siedlisk/MapServer/20)
- [BDL – Mapa drzewostanów, lista warstw (w tym utwory geologiczne 69)](http://mapserver.bdl.lasy.gov.pl/arcgis/rest/services/Mapa_drzewostanow/MapServer)
- [BDL – usługi mapowe OGC (WMS/WMTS)](https://www9.bdl.lasy.gov.pl/portal/uslugi-mapowe-ogc)
- [Open-Meteo – przegląd API i zmiennych](https://open-meteo.com/en/features)
