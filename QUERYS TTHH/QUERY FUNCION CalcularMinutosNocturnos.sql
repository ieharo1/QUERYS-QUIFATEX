CREATE FUNCTION dbo.CalcularMinutosNocturnos(@FechaIn DATETIME, @FechaOut DATETIME)
RETURNS INT
AS
BEGIN
    DECLARE @MinutosNocturnos INT = 0;
    DECLARE @HoraIn TIME = CAST(@FechaIn AS TIME);
    DECLARE @HoraOut TIME = CAST(@FechaOut AS TIME);
    DECLARE @FechaInDate DATE = CAST(@FechaIn AS DATE);
    DECLARE @FechaOutDate DATE = CAST(@FechaOut AS DATE);

    -- Si es el mismo día
    IF @FechaInDate = @FechaOutDate
    BEGIN
        -- Trabaja entre 19:00 y 23:59 del mismo día
        IF @HoraIn < '19:00:00' AND @HoraOut > '19:00:00'
            SET @MinutosNocturnos = DATEDIFF(MINUTE, '19:00:00', @HoraOut);
        ELSE IF @HoraIn >= '19:00:00'
            SET @MinutosNocturnos = DATEDIFF(MINUTE, @HoraIn, @HoraOut);
    END
    ELSE
    BEGIN -- Días diferentes (trabaja pasado la medianoche)
        -- Horas nocturnas del día de entrada (desde 19:00 hasta 23:59)
        IF @HoraIn < '19:00:00'
            SET @MinutosNocturnos = DATEDIFF(MINUTE, '19:00:00', '23:59:59');
        ELSE
            SET @MinutosNocturnos = DATEDIFF(MINUTE, @HoraIn, '23:59:59');
        
        -- Horas nocturnas del día de salida (desde 00:00 hasta 06:00)
        IF @HoraOut <= '06:00:00'
            SET @MinutosNocturnos = @MinutosNocturnos + DATEDIFF(MINUTE, '00:00:00', @HoraOut);
        ELSE
            SET @MinutosNocturnos = @MinutosNocturnos + DATEDIFF(MINUTE, '00:00:00', '06:00:00');
    END

    -- Asegurar que no sea negativo
    IF @MinutosNocturnos < 0 SET @MinutosNocturnos = 0;

    RETURN @MinutosNocturnos;
END