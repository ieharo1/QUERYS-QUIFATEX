CREATE FUNCTION dbo.CalcularMinutosSuplementarios(@FechaIn DATETIME, @FechaOut DATETIME)
RETURNS INT
AS
BEGIN
    DECLARE @MinutosSuplementarios INT = 0;
    DECLARE @MinutosTrabajados INT = DATEDIFF(MINUTE, @FechaIn, @FechaOut);
    DECLARE @MinutosJornadaNormal INT = (8 * 60) + 45; -- 8 horas + 45min almuerzo
    
    -- Si trabajó más de la jornada normal
    IF @MinutosTrabajados > @MinutosJornadaNormal
    BEGIN
        SET @MinutosSuplementarios = @MinutosTrabajados - @MinutosJornadaNormal;
        
        -- Máximo 4 horas (240 minutos)
        IF @MinutosSuplementarios > 240
            SET @MinutosSuplementarios = 240;
    END
    
    RETURN @MinutosSuplementarios;
END