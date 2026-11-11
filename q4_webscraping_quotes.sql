-- Database: WebScarpping_Q4.3

-- DROP DATABASE IF EXISTS "WebScarpping_Q4.3";

CREATE DATABASE "WebScarpping_Q4.3"
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'English_South Africa.1252'
    LC_CTYPE = 'English_South Africa.1252'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

CREATE TABLE quote_listings(
quote_ID SERIAL PRIMARY KEY,
quote_text TEXT NOT NULL,
author VARCHAR(255) NOT NULL,
word_count INT NOT NULL,
numeric_tags INT NOT NULL
);

SELECT COUNT(*) FROM quote_listings;
SELECT * FROM quote_listings;

--SQL analytical Investigation 1 : Author Productivity and Verbosity
SELECT
    author,
    COUNT(*)                    AS total_quotes,
    ROUND(AVG(word_count), 1)   AS avg_word_count,
    SUM(numeric_tags)           AS total_tags
FROM quote_listings
GROUP BY author
HAVING COUNT(*) > 1
ORDER BY total_quotes DESC, avg_word_count DESC;

-- SQL analytical Investigation 2 : Catogorization by Complexity
SELECT
    CASE
        WHEN word_count > (SELECT AVG(word_count) FROM quote_listings)
            THEN 'Detailed Quote'
        ELSE 'Concise Quote'
    END                          AS complexity_tier,
    COUNT(*)                     AS total_quotes,
    ROUND(AVG(word_count), 1)    AS avg_word_count,
    MIN(word_count)              AS shortest,
    MAX(word_count)              AS longest,
    ROUND(AVG(numeric_tags), 1)  AS avg_tags
FROM quote_listings
GROUP BY complexity_tier
ORDER BY avg_word_count DESC;