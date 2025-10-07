CREATE FUNCTION dbo.CalcularMinutosDiaFestivo(@FechaIn DATETIME, @FechaOut DATETIME, @FechaFestivo DATE)
RETURNS INT
AS
BEGIN
    DECLARE @MinutosFestivo INT = 0;
    DECLARE @HoraIn TIME = CAST(@FechaIn AS TIME);
    DECLARE @HoraOut TIME = CAST(@FechaOut AS TIME);
    DECLARE @FechaInDate DATE = CAST(@FechaIn AS DATE);
    DECLARE @FechaOutDate DATE = CAST(@FechaOut AS DATE);

    -- Si inicio y fin son en el mismo d�a festivo
    IF @FechaInDate = @FechaFestivo AND @FechaOutDate = @FechaFestivo
    BEGIN
        SET @MinutosFestivo = DATEDIFF(MINUTE, @FechaIn, @FechaOut);
    END
    -- Si inicia en d�a festivo pero termina al d�a siguiente
    ELSE IF @FechaInDate = @FechaFestivo AND @FechaOutDate > @FechaFestivo
    BEGIN
        -- Cuenta hasta las 00:00:00 del d�a siguiente (que es el final del d�a festivo)
        SET @MinutosFestivo = DATEDIFF(MINUTE, @FechaIn, DATEADD(DAY, 1, CAST(@FechaFestivo AS DATETIME)));
    END
    -- Si inicia antes del d�a festivo pero termina en d�a festivo
    ELSE IF @FechaInDate < @FechaFestivo AND @FechaOutDate = @FechaFestivo
    BEGIN
        -- Cuenta desde las 00:00:00 del d�a festivo
        SET @MinutosFestivo = DATEDIFF(MINUTE, CAST(@FechaFestivo AS DATETIME), @FechaOut);
    END

    -- Asegurar que no sea negativo
    IF @MinutosFestivo < 0 SET @MinutosFestivo = 0;

    RETURN @MinutosFestivo;
END