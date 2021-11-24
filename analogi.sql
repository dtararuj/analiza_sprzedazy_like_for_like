-- Table: public.baza

CREATE TABLE IF NOT EXISTS public.baza
(
    "Data" date NOT NULL,
    "Sklep" character(35) COLLATE pg_catalog."default" NOT NULL,
    "Region" character(35) COLLATE pg_catalog."default",
    "Obrot_brutto" numeric(10,2),
    "Obrot_netto" numeric(10,2),
    "Marza_netto" numeric(10,2),
    "Marza%" numeric(6,2),
    "Zwroty_brutto" numeric(8,2),
    "zwrotow%" numeric(5,2),
    "Plan" numeric(8,2),
    "realizacji_planu%" numeric(6,2),
    "Ilosc_sztuk" smallint,
    "Ilosc_paragonow" smallint,
    "Sztuka" numeric(6,2),
    "Check" numeric(4,2),
    "Koszyk" numeric(6,2),
    "Skutecznosc" numeric(6,2),
    "Wejscia" smallint,
    CONSTRAINT baza_pkey PRIMARY KEY ("Data", "Sklep")
)

TABLESPACE pg_default;

ALTER TABLE public.baza
    OWNER to postgres;
	
-- 1. Przygotowanie danych:
-- a) czyszczenie bazy ze zbednych kolumn,

CREATE TABLE IF NOT EXISTS public.analogi AS
	SELECT
	 "Data",
	 "Sklep",
	 "Obrot_netto" as "obrot",
	 "Marza_netto" as "GM",
	 "realizacji_planu%" as "plan",
	 "Ilosc_sztuk" as "ilosc",
	 "Ilosc_paragonow",
	 "Sztuka"  	   as "AUR",
	 "Check",
	 "Koszyk",
	 "Skutecznosc",
	 "Wejscia"
	FROM baza;

-- b) dopisanie roku, tygodnia, miesiaca i dnia tygodnia oraz tygodnia przesunietego do porownan (ze względu na inny układ dni w roku),
-- c) wskazanie czy dany sklep moze byc analogiem dla porownania lfl [do 2020r] ze względu na jego datę otwarcia (analogiem
-- może być sklep, który był czynny przez cały poprzedni rok i odntotował sprzedaż w porównywalnym okresie),
-- d) stworzenie tabeli tymczasowej

CREATE temp table robocza_1 AS(

	WITH CTE AS(

		SELECT *,
		  EXTRACT (year FROM analogi."Data")  AS rok,
		  EXTRACT (month FROM analogi."Data") AS miesiac,
		  EXTRACT (week FROM analogi."Data")  AS tydzien,
		  EXTRACT (dow FROM analogi."Data")   AS nr_dnia,
		  TO_CHAR(analogi."Data", 'day') 	  AS dzien
		FROM analogi
		JOIN (SELECT
				"Miasto",
				"Data"						  AS "data_otwarcia"
			  FROM daty
			  ) as dt
		  ON analogi."Sklep" = dt."Miasto" 
	), CTE2 AS(

		SELECT *,
		  CASE
			WHEN rok < 2021
			  THEN tydzien -1
			ELSE tydzien
		  END tydz_przesuniety
		FROM CTE

	)

		SELECT *,
		  CASE
			WHEN tydz_przesuniety = 0
			  THEN 52
			ELSE tydz_przesuniety
		  END tydz_przesuniety1,
		  CASE
			WHEN EXTRACT(year FROM data_otwarcia) +1 < rok
			  THEN 'tak'
			ELSE 'nie'
		  END czy_analog,
		  CASE
			WHEN tydz_przesuniety = 53 AND miesiac = 1
			  THEN rok -1
			ELSE rok
		  END rok1
		FROM CTE2
		ORDER BY rok1, tydz_przesuniety ASC
);
	
-- 2. Przypisanie miana sklepu analogicznego
-- Sklepem analogicznym, do porównywania lfl możemy nazwać taki salon, 
-- który był czynny przez cały poprzedni rok, ale też w analogicznym tygodniu roku poprzedniego był czynny/miał obroty.
-- W tym miejscu wykluczymy z porównań dla danych tygodni sklepy, które były zamknięte z powodu lockdownu

-- a) oczyścmy tabele robaczą ze zbednych kolumn

ALTER TABLE robocza_1 
	DROP COLUMN "Miasto",
	DROP COLUMN "tydz_przesuniety",
	DROP COLUMN "rok"
	;
	
--b) pogrupujmy sprzedaz per tydzien
CREATE TEMP TABLE pogrupowane AS(

	SELECT 
		"Sklep",
		"rok1" AS rok,
		"tydz_przesuniety1" as tydz_przes,
		SUM("obrot") AS obrot,
		"rok1" - 1 AS rok_poprz
	FROM robocza_1
	GROUP BY 
		"Sklep",
		"rok1",
		"tydz_przesuniety1",
		"rok_poprz"
);
	
-- c) dodajemy sprzedaz za zeszly rok dla danego tygodnia

CREATE TEMP TABLE obrot_poprz AS(

	WITH part AS(

		SELECT *
		FROM pogrupowane as pg1
		LEFT JOIN 
		  (SELECT
			"Sklep" AS sklep_1,
			"tydz_przes" AS tydz_przes_1,
			"rok" AS rok_1,
			"obrot" AS obrot_1
		  FROM pogrupowane) as pg2
		  ON pg1."Sklep" = pg2."sklep_1"
			AND pg1."tydz_przes" = pg2."tydz_przes_1"
			AND pg1."rok_poprz" = pg2."rok_1"
	)

		SELECT
		  "Sklep",
		  "rok",
		  "tydz_przes",
		  "obrot",
		  "obrot_1" AS obrot_poprz
		 FROM part
);


-- d) w tym kroku połączmy główną tabele, tj. robacza1, z wyliczonymi wartosciami za poprzedni rok z tabeli obrot poprz

CREATE TEMP TABLE pelne_zestawienie AS(

	WITH tymczas AS(

		SELECT * FROM robocza_1 AS r1
		LEFT JOIN 
		  (SELECT
			 "Sklep" AS sklep1,
			 "rok",
			 "tydz_przes",
			 "obrot_poprz"
		   FROM obrot_poprz)	AS op
		  ON r1."Sklep" = op."sklep1" 
		  AND r1."rok1"  = op."rok"  
		  AND r1."tydz_przesuniety1" = op."tydz_przes"

	)
		SELECT *,
		  CASE 
			WHEN "obrot_poprz" IS NOT NULL AND "czy_analog" = 'tak'
			  THEN 'tak'
			ELSE 'nie' 
		  END czy_analog1
		FROM tymczas
);

-- 3. Przygotowanie finalnych danych do podsumowania
-- a) odfiltrowanie zbednych kolumn i pogrupowanie danych po dniu

CREATE TABLE dane_na_dzien AS(

	WITH tymczas1 AS(

		SELECT 
		  "Data",
		  "obrot",
		  "GM",
		  "plan",
		  "ilosc",
		  "Ilosc_paragonow",
		  "Wejscia",
		  "miesiac",
		  "tydzien",
		  "nr_dnia",
		  "tydz_przes",
		  "rok",
		  "czy_analog1" AS "czy_analog"
		FROM pelne_zestawienie 

	)	
		SELECT 
		  "Data",
		  "miesiac",
		  "tydzien",
		  "nr_dnia",
		  "tydz_przes",
		  "rok",
		  "czy_analog",
		  SUM("obrot")				AS obrot,
		  SUM("GM")					AS gm,
		  SUM("plan")				AS plan,
		  SUM("ilosc")				AS slsu,
		  SUM("Ilosc_paragonow")	AS n_paragonow,
		  SUM("Wejscia")			AS trafik
		FROM tymczas1
		GROUP BY
		  "Data",
		  "miesiac",
		  "tydzien",
		  "nr_dnia",
		  "tydz_przes",
		  "rok",
		  "czy_analog"
		ORDER BY "Data"
	
);	  

-- 4. Przygotowanie roznych widokow

-- sprzedaz sklepow analogicznych po tygodniu

CREATE VIEW v_lfl20_per_week AS(

	WITH tymczas2 AS(

		SELECT 
		  "rok",
		  "tydz_przes",
		  "czy_analog",
		  SUM("obrot")				AS obrot,
		  SUM("gm")					AS gm,
		  SUM("plan")				AS plan,
		  SUM("slsu")				AS slsu,
		  SUM("n_paragonow")		AS n_paragonow,
		  SUM("trafik")				AS trafik
		FROM dane_na_dzien
		WHERE "czy_analog" = 'tak'
		  AND trafik >0
		GROUP BY "tydz_przes", "rok","czy_analog"
		ORDER BY "rok", "tydz_przes"

	)
		SELECT *,
		  ROUND("n_paragonow"/"trafik",3)	AS skutecznosc,
		  ROUND("slsu"/"n_paragonow",2)		AS "check",
		  ROUND("obrot"/"n_paragonow",2)	AS koszyk,
		  ROUND("obrot"/"slsu",2)			AS sztuka,
		  ROUND("gm"/"obrot",4)				AS gm_proc
		 FROM tymczas2														

);


SELECT * FROM v_lfl20_per_week;

-- sprzedaz analogiczna za ostatni tydzien

SELECT
  "rok",
  "tydz_przes" AS tydz,
  "obrot",
  "gm",
  "trafik",
  1-round(LAG ("obrot") OVER (ORDER BY "rok")/"obrot",2) AS obrot_rr,
  1-round(LAG ("gm") OVER (ORDER BY "rok")/"gm",2) AS marza_rr,
  1-round(LAG ("trafik") OVER (ORDER BY "rok")/"trafik",2) AS trafik_rr
FROM v_lfl20_per_week
WHERE rok IN (2021,2020) 
  AND tydz_przes = '25'
  
-- sprzedaz analogiczna za ostatni miesiac

-- sprzedaz sklepow analogicznych po tygodniu

CREATE VIEW v_lfl20_per_month AS(

	WITH tymczas3 AS(

		SELECT 
		  "rok",
		  "miesiac",
		  "czy_analog",
		  SUM("obrot")				AS obrot,
		  SUM("gm")					AS gm,
		  SUM("plan")				AS plan,
		  SUM("slsu")				AS slsu,
		  SUM("n_paragonow")		AS n_paragonow,
		  SUM("trafik")				AS trafik
		FROM dane_na_dzien
		WHERE "czy_analog" = 'tak'
		  AND trafik >0
		GROUP BY "miesiac", "rok","czy_analog"
		ORDER BY "rok", "miesiac"

	)
		SELECT *,
		  ROUND("n_paragonow"/"trafik",3)	AS skutecznosc,
		  ROUND("slsu"/"n_paragonow",2)		AS "check",
		  ROUND("obrot"/"n_paragonow",2)	AS koszyk,
		  ROUND("obrot"/"slsu",2)			AS sztuka,
		  ROUND("gm"/"obrot",4)				AS gm_proc
		 FROM tymczas3													

);

SELECT
  "rok",
  "miesiac",
  "obrot",
  "gm",
  "trafik",
  1-round(LAG ("obrot") OVER (ORDER BY "rok")/"obrot",2) AS obrot_rr,
  1-round(LAG ("gm") OVER (ORDER BY "rok")/"gm",2) AS marza_rr,
  1-round(LAG ("trafik") OVER (ORDER BY "rok")/"trafik",2) AS trafik_rr
FROM v_lfl20_per_month
WHERE rok IN (2021,2020) 
  AND miesiac = '5'