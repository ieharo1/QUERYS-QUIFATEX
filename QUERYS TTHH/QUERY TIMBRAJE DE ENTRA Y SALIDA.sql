--////////////////////////////////////////////
--
--QUERY PARA INGRESAR LAS FECHAS VERSION 1.0
--
--////////////////////////////////////////////
SET NOCOUNT ON;
 
DECLARE 
    @FECHA_I DATE = '2025-08-01',
    @FECHA_F DATE = '2025-08-16';
 
-- 1) Agrupar una vez por persona+día (min/max y cuenta)
IF OBJECT_ID('tempdb..#REG_DAILY') IS NOT NULL DROP TABLE #REG_DAILY;
 
SELECT
    R.REG_IDENTIFICACION,
    R.REG_NOMBRE,
    R.REG_ID_USUARIO,
    CONVERT(DATE, R.REG_FECHA) AS REG_DATE,
    MIN(R.REG_FECHA) AS FECHA_IN_DAY,
    MAX(R.REG_FECHA) AS FECHA_OUT_DAY,
    COUNT(*) AS CNT
INTO #REG_DAILY
FROM TBL_REGISTRO R
WHERE CONVERT(DATE, R.REG_FECHA) BETWEEN @FECHA_I AND @FECHA_F
GROUP BY
    R.REG_IDENTIFICACION,
    R.REG_NOMBRE,
    R.REG_ID_USUARIO,
    CONVERT(DATE, R.REG_FECHA);
 
CREATE INDEX IX_REG_DAILY_IDENT_DATE ON #REG_DAILY(REG_IDENTIFICACION, REG_DATE);
 
 
-- 2) ADMINISTRATIVOS (THO_ID = 3) -> insertar min/max del mismo día
INSERT INTO TBL_TIMBRE (
    TIM_FECHA,
    TIM_IDENTIFICACION,
    TIM_NOMBRE,
    TIM_ID_USUARIO,
    TIM_FECHA_IN,
    TIM_FECHA_OUT,
    TIM_ESTADO,
    TIM_OBSERVACION
)
SELECT
    d.REG_DATE AS TIM_FECHA,
    d.REG_IDENTIFICACION,
    d.REG_NOMBRE,
    d.REG_ID_USUARIO,
    d.FECHA_IN_DAY,
    CASE WHEN d.FECHA_IN_DAY = d.FECHA_OUT_DAY THEN NULL ELSE d.FECHA_OUT_DAY END,
    'ADMINISTRATIVO',
    CASE WHEN d.FECHA_IN_DAY = d.FECHA_OUT_DAY THEN 'FALTA SALIDA' ELSE 'OK' END
FROM #REG_DAILY d
INNER JOIN TBL_COLABORADOR c
    ON c.COL_IDENTIFICACION = d.REG_IDENTIFICACION
WHERE c.THO_ID = 3
  -- evitar insertar si ya existe registro para ese día y persona
  AND NOT EXISTS (
      SELECT 1 FROM TBL_TIMBRE t
      WHERE t.TIM_IDENTIFICACION = d.REG_IDENTIFICACION
        AND t.TIM_FECHA = d.REG_DATE
  );
 
 
-- 3) PREPARAR CANDIDATOS PARA OPERATIVOS (THO_ID = 2)
IF OBJECT_ID('tempdb..#OPER_CAND') IS NOT NULL DROP TABLE #OPER_CAND;
 
SELECT
    d.REG_IDENTIFICACION,
    d.REG_NOMBRE,
    d.REG_ID_USUARIO,
    d.REG_DATE,
    d.FECHA_IN_DAY,
    d.FECHA_OUT_DAY,
    -- buscar la salida más cercana > FECHA_IN_DAY y <= 15 horas
    OUTR.FECHA_OUT
INTO #OPER_CAND
FROM #REG_DAILY d
INNER JOIN TBL_COLABORADOR c
    ON c.COL_IDENTIFICACION = d.REG_IDENTIFICACION
OUTER APPLY (
    SELECT TOP 1 r2.REG_FECHA AS FECHA_OUT
    FROM TBL_REGISTRO r2
    WHERE r2.REG_IDENTIFICACION = d.REG_IDENTIFICACION
      AND r2.REG_FECHA > d.FECHA_IN_DAY
      AND DATEDIFF(HOUR, d.FECHA_IN_DAY, r2.REG_FECHA) BETWEEN 1 AND 15
    ORDER BY r2.REG_FECHA ASC
) OUTR
WHERE c.THO_ID = 2;  -- solo operativos
 
CREATE INDEX IX_OPER_CAND_IDENT_ONFECHAOUT ON #OPER_CAND(REG_IDENTIFICACION, FECHA_OUT);
 
 
-- 4) Insertar operativos, excluyendo:
--    a) si ya existe TIM_FECHA para esa persona+fecha
--    b) si FECHA_IN ya fue usada como TIM_FECHA_OUT (registro previo en TBL_TIMBRE)
--    c) si FECHA_IN coincide con la FECHA_OUT de otra fila dentro de #OPER_CAND (evita el caso 16:07->00:43 y luego 00:43 como nueva entrada)
INSERT INTO TBL_TIMBRE (
    TIM_FECHA,
    TIM_IDENTIFICACION,
    TIM_NOMBRE,
    TIM_ID_USUARIO,
    TIM_FECHA_IN,
    TIM_FECHA_OUT,
    TIM_ESTADO,
    TIM_OBSERVACION
)
SELECT
    oc.REG_DATE AS TIM_FECHA,
    oc.REG_IDENTIFICACION,
    oc.REG_NOMBRE,
    oc.REG_ID_USUARIO,
    oc.FECHA_IN_DAY,
    oc.FECHA_OUT,
    'OPERATIVO',
    CASE WHEN oc.FECHA_OUT IS NULL THEN 'FALTA SALIDA' ELSE 'OK' END
FROM #OPER_CAND oc
WHERE 
    -- a) no exista ya registro para ese dia
    NOT EXISTS (
        SELECT 1 FROM TBL_TIMBRE t
        WHERE t.TIM_IDENTIFICACION = oc.REG_IDENTIFICACION
          AND t.TIM_FECHA = oc.REG_DATE
    )
    -- b) la FECHA_IN no haya sido usada como TIM_FECHA_OUT en la tabla ya existente
    AND NOT EXISTS (
        SELECT 1 FROM TBL_TIMBRE t2
        WHERE t2.TIM_IDENTIFICACION = oc.REG_IDENTIFICACION
          AND t2.TIM_FECHA_OUT = oc.FECHA_IN_DAY
    )
    -- c) la FECHA_IN no sea FECHA_OUT de otra fila dentro del batch (evita insertar la fila que fue salida la noche anterior)
    AND NOT EXISTS (
        SELECT 1 FROM #OPER_CAND oc2
        WHERE oc2.REG_IDENTIFICACION = oc.REG_IDENTIFICACION
          AND oc2.FECHA_OUT IS NOT NULL
          AND oc2.FECHA_OUT = oc.FECHA_IN_DAY
    );
 
 
-- limpieza
DROP TABLE #REG_DAILY;
DROP TABLE #OPER_CAND;
 
SET NOCOUNT OFF;

--////////////////////////////////////////////
--
--QUERY PARA INGRESAR LAS FECHAS VERSION 2.0
--
--////////////////////////////////////////////
SET NOCOUNT ON;

DECLARE 
    @FECHA_I DATE = '2025-01-01',
    @FECHA_F DATE = '2025-08-16';

-- ===========================================================
-- 0) Prepara: cargamos registros del rango (incluimos +1 día para capturar salidas del día siguiente)
-- ===========================================================
IF OBJECT_ID('tempdb..#REG_BASE') IS NOT NULL DROP TABLE #REG_BASE;

SELECT
    R.REG_IDENTIFICACION,
    R.REG_NOMBRE,
    R.REG_ID_USUARIO,
    R.REG_FECHA,
    C.THO_ID
INTO #REG_BASE
FROM TBL_REGISTRO R
INNER JOIN TBL_COLABORADOR C ON C.COL_IDENTIFICACION = R.REG_IDENTIFICACION
WHERE R.REG_FECHA BETWEEN @FECHA_I AND DATEADD(DAY, 1, @FECHA_F);  -- incluir siguiente día para emparejamientos nocturnos

CREATE INDEX IX_REG_BASE_IDENT_FECHA ON #REG_BASE(REG_IDENTIFICACION, REG_FECHA);


-- ===========================================================
-- 1) ADMINISTRATIVOS (THO_ID = 3) -> min/max por día (igual que antes)
-- ===========================================================
;WITH ADMIN_CTE AS (
    SELECT
        REG_IDENTIFICACION,
        REG_NOMBRE,
        REG_ID_USUARIO,
        CONVERT(DATE, REG_FECHA) AS DIA,
        MIN(REG_FECHA) AS FECHA_IN,
        MAX(REG_FECHA) AS FECHA_OUT
    FROM #REG_BASE
    WHERE THO_ID = 3
    GROUP BY REG_IDENTIFICACION, REG_NOMBRE, REG_ID_USUARIO, CONVERT(DATE, REG_FECHA)
)
INSERT INTO TBL_TIMBRE (
    TIM_FECHA,
    TIM_IDENTIFICACION,
    TIM_NOMBRE,
    TIM_ID_USUARIO,
    TIM_FECHA_IN,
    TIM_FECHA_OUT,
    TIM_ESTADO,
    TIM_OBSERVACION
)
SELECT
    A.DIA,
    A.REG_IDENTIFICACION,
    A.REG_NOMBRE,
    A.REG_ID_USUARIO,
    A.FECHA_IN,
    CASE WHEN A.FECHA_IN = A.FECHA_OUT THEN NULL ELSE A.FECHA_OUT END,
    'ADMINISTRATIVO',
    CASE WHEN A.FECHA_IN = A.FECHA_OUT THEN 'FALTA SALIDA' ELSE 'OK' END
FROM ADMIN_CTE A
WHERE NOT EXISTS (
    SELECT 1 FROM TBL_TIMBRE T
    WHERE T.TIM_IDENTIFICACION = A.REG_IDENTIFICACION
      AND T.TIM_FECHA = A.DIA
);


-- ===========================================================
-- 2) OPERATIVOS (THO_ID = 2) - Emparejado greedy seguro
--    Regla principal: una fila R es inicio (FECHA_IN) si:
--      - PREV_FECHA es NULL OR DATEDIFF_MINUTE(PREV_FECHA, R.REG_FECHA) > 900
--      - NEXT_FECHA existe AND DATEDIFF_MINUTE(R.REG_FECHA, NEXT_FECHA) BETWEEN 1 AND 900
--    (esto evita que una FECHA_OUT usada por PREV sea tomada como FECHA_IN)
-- ===========================================================
;WITH OPE_WINDOW AS (
    SELECT 
        REG_IDENTIFICACION,
        REG_NOMBRE,
        REG_ID_USUARIO,
        REG_FECHA,
        LAG(REG_FECHA) OVER (PARTITION BY REG_IDENTIFICACION ORDER BY REG_FECHA) AS PREV_FECHA,
        LEAD(REG_FECHA) OVER (PARTITION BY REG_IDENTIFICACION ORDER BY REG_FECHA) AS NEXT_FECHA
    FROM #REG_BASE
    WHERE THO_ID = 2
),
OPE_STARTS AS (
    SELECT
        REG_IDENTIFICACION,
        REG_NOMBRE,
        REG_ID_USUARIO,
        REG_FECHA AS FECHA_IN,
        NEXT_FECHA AS FECHA_OUT,
        CONVERT(DATE, REG_FECHA) AS DIA
    FROM OPE_WINDOW
    WHERE 
        -- PREV no debe ser un registro que empareje con ésta (si PREV empareja con ésta, ésta fue salida)
        (PREV_FECHA IS NULL OR DATEDIFF(MINUTE, PREV_FECHA, REG_FECHA) > 900)
        -- NEXT debe existir y estar dentro del límite de 15 horas (en minutos)
        AND (NEXT_FECHA IS NOT NULL AND DATEDIFF(MINUTE, REG_FECHA, NEXT_FECHA) BETWEEN 1 AND 900)
)
-- Insertar parejas válidas (OK)
INSERT INTO TBL_TIMBRE (
    TIM_FECHA,
    TIM_IDENTIFICACION,
    TIM_NOMBRE,
    TIM_ID_USUARIO,
    TIM_FECHA_IN,
    TIM_FECHA_OUT,
    TIM_ESTADO,
    TIM_OBSERVACION
)
SELECT
    S.DIA,
    S.REG_IDENTIFICACION,
    S.REG_NOMBRE,
    S.REG_ID_USUARIO,
    S.FECHA_IN,
    S.FECHA_OUT,
    'OPERATIVO',
    'OK'
FROM OPE_STARTS S
WHERE
    -- no duplicar si ya existe exactamente ese par
    NOT EXISTS (
        SELECT 1 FROM TBL_TIMBRE T
        WHERE T.TIM_IDENTIFICACION = S.REG_IDENTIFICACION
          AND T.TIM_FECHA_IN = S.FECHA_IN
          AND T.TIM_FECHA_OUT = S.FECHA_OUT
    )
    -- adicional: la FECHA_IN no debe ser ya FECHA_OUT en TBL_TIMBRE (evitar reutilizar salida previa)
    AND NOT EXISTS (
        SELECT 1 FROM TBL_TIMBRE T2
        WHERE T2.TIM_IDENTIFICACION = S.REG_IDENTIFICACION
          AND T2.TIM_FECHA_OUT = S.FECHA_IN
    );

-- ===========================================================
-- 3) (Opcional) Insertar "FALTA SALIDA" para inicios que no encontraron salida
--    (son filas que no fueron usadas como FECHA_OUT por prev y tampoco tienen next válido)
-- ===========================================================
;WITH OPE_PENDING AS (
    SELECT
        REG_IDENTIFICACION,
        REG_NOMBRE,
        REG_ID_USUARIO,
        REG_FECHA AS FECHA_IN,
        CONVERT(DATE, REG_FECHA) AS DIA,
        LAG(REG_FECHA) OVER (PARTITION BY REG_IDENTIFICACION ORDER BY REG_FECHA) AS PREV_FECHA,
        LEAD(REG_FECHA) OVER (PARTITION BY REG_IDENTIFICACION ORDER BY REG_FECHA) AS NEXT_FECHA
    FROM #REG_BASE
    WHERE THO_ID = 2
)
INSERT INTO TBL_TIMBRE (
    TIM_FECHA,
    TIM_IDENTIFICACION,
    TIM_NOMBRE,
    TIM_ID_USUARIO,
    TIM_FECHA_IN,
    TIM_FECHA_OUT,
    TIM_ESTADO,
    TIM_OBSERVACION
)
SELECT
    P.DIA,
    P.REG_IDENTIFICACION,
    P.REG_NOMBRE,
    P.REG_ID_USUARIO,
    P.FECHA_IN,
    NULL,
    'OPERATIVO',
    'FALTA SALIDA'
FROM OPE_PENDING P
WHERE
    -- no fue usado como salida por el previo
    (P.PREV_FECHA IS NULL OR DATEDIFF(MINUTE, P.PREV_FECHA, P.FECHA_IN) > 900)
    -- no tiene NEXT válido dentro de 15h
    AND (P.NEXT_FECHA IS NULL OR DATEDIFF(MINUTE, P.FECHA_IN, P.NEXT_FECHA) > 900)
    -- y no exista ya registro para ese día (evitar duplicados)
    AND NOT EXISTS (
        SELECT 1 FROM TBL_TIMBRE T
        WHERE T.TIM_IDENTIFICACION = P.REG_IDENTIFICACION
          AND T.TIM_FECHA = P.DIA
    )
    -- y no sea a su vez FECHA_OUT ya registrada (por seguridad)
    AND NOT EXISTS (
        SELECT 1 FROM TBL_TIMBRE T2
        WHERE T2.TIM_IDENTIFICACION = P.REG_IDENTIFICACION
          AND T2.TIM_FECHA_OUT = P.FECHA_IN
    );


-- limpieza
DROP TABLE #REG_BASE;

SET NOCOUNT OFF;

--////////////////////////////////////////////////
--CONSULTAS
--////////////////////////////////////////////////

TRUNCATE TABLE TBL_TIMBRE;

SELECT * FROM TBL_REGISTRO WHERE REG_IDENTIFICACION = '0201707452';
SELECT * FROM TBL_TIMBRE WHERE TIM_IDENTIFICACION = '0401532296' ORDER BY TIM_FECHA_IN ASC;
SELECT * FROM TBL_REPORTE;

SELECT * FROM TBL_REGISTRO WHERE REG_IDENTIFICACION = '1003094685';
SELECT * FROM TBL_TIMBRE WHERE TIM_IDENTIFICACION = '0201707452' ORDER BY TIM_FECHA_IN ASC;

SELECT * FROM TBL_TIMBRE ORDER BY TIM_IDENTIFICACION, TIM_FECHA_IN, TIM_ESTADO ASC;

SELECT * FROM TBL_REGISTRO WHERE REG_IDENTIFICACION = '0401024211';
