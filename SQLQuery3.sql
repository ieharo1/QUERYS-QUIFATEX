--BUSQUEDA POR LEVENSHTEIN
--CREA UNA FUNCION EN LA BASE
CREATE OR ALTER FUNCTION dbo.Levenshtein(@s NVARCHAR(100), @t NVARCHAR(100))
RETURNS INT
AS
BEGIN
    DECLARE @sLen INT = LEN(@s), 
            @tLen INT = LEN(@t), 
            @i INT, 
            @j INT, 
            @cost INT;

    IF @sLen = 0 RETURN @tLen;
    IF @tLen = 0 RETURN @sLen;

    DECLARE @dist TABLE (i INT, j INT, val INT);

    -- Inicializar primera columna
    SET @i = 0;
    WHILE @i <= @sLen
    BEGIN
        INSERT INTO @dist(i, j, val) VALUES(@i, 0, @i);
        SET @i += 1;
    END

    -- Inicializar primera fila
    SET @j = 0;
    WHILE @j <= @tLen
    BEGIN
        INSERT INTO @dist(i, j, val) VALUES(0, @j, @j);
        SET @j += 1;
    END

    -- Calcular matriz
    SET @i = 1;
    WHILE @i <= @sLen
    BEGIN
        SET @j = 1;
        WHILE @j <= @tLen
        BEGIN
            SET @cost = CASE WHEN SUBSTRING(@s, @i, 1) = SUBSTRING(@t, @j, 1) THEN 0 ELSE 1 END;

            DECLARE @val INT;
            SELECT @val = MIN(v)
            FROM (
                SELECT val + 1 AS v FROM @dist WHERE i = @i - 1 AND j = @j
                UNION ALL
                SELECT val + 1 FROM @dist WHERE i = @i AND j = @j - 1
                UNION ALL
                SELECT val + @cost FROM @dist WHERE i = @i - 1 AND j = @j - 1
            ) a;

            INSERT INTO @dist(i, j, val) VALUES(@i, @j, @val);
            SET @j += 1;
        END
        SET @i += 1;
    END

    DECLARE @result INT;
    SELECT TOP 1 @result = val FROM @dist WHERE i = @sLen AND j = @tLen;
    RETURN @result;
END;


--BUSQUEDA POR FONETICA Y LEVENSHTEIN
--USA LA FUNCION FONETICA Y LEVENSHTEIN QUE SALE AHI
DECLARE @i_varProducto NVARCHAR(100) = 'SERABE';
DECLARE @maxLevDist INT = 3;       
DECLARE @minSimilarity FLOAT = 0.60;
DECLARE @maxResults INT = 3;

;WITH Matches AS
(
    SELECT
        P.PRODUCTO,
        P.ESPECIALIDAD,
        P.GESTOR,
        dbo.Levenshtein(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(P.PRODUCTO))),'.',''),'/', ''),'-',''),'(',''),')',''),
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(@i_varProducto))),'.',''),'/', ''),'-',''),'(',''),')','')
        ) AS LevDist,
        DIFFERENCE(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(P.PRODUCTO))),'.',''),'/', ''),'-',''),'(',''),')',''),
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(@i_varProducto))),'.',''),'/', ''),'-',''),'(',''),')','')
        ) AS DiffScore,
        CASE WHEN SOUNDEX(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(P.PRODUCTO))),'.',''),'/', ''),'-',''),'(',''),')','')
        ) = SOUNDEX(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(LTRIM(RTRIM(@i_varProducto))),'.',''),'/', ''),'-',''),'(',''),')','')
        ) THEN 1 ELSE 0 END AS SoundexMatch
    FROM vw_esp_prd_ven_sBot AS P
)
SELECT TOP (@maxResults)
    PRODUCTO,
    ESPECIALIDAD,
    GESTOR
FROM Matches
WHERE 
    LevDist <= @maxLevDist
    OR DiffScore >= 3
    OR SoundexMatch = 1
    OR (1.0 - (CAST(LevDist AS FLOAT) / NULLIF(LEN(PRODUCTO),0))) >= @minSimilarity
ORDER BY 
    -- ordenar por una combinación simple: primero distancia, luego diferencia fonética
    ( (1.0 - (CAST(LevDist AS FLOAT) / NULLIF(LEN(PRODUCTO),0))) * 0.75
    + (CAST(DiffScore AS FLOAT)/4.0 * 0.20)
    + (SoundexMatch * 0.05) ) DESC;
