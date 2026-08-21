-- ============================================================
-- arcade — habilitar los ocho juegos restantes
-- ============================================================
-- Se aplica cuando modules/arcadeGames.py ya esta desplegado. Idempotente.
--
-- OJO con el orden: sp_arcadeRounds_open rechaza cualquier juego con
-- comingSoon = '1', asi que desbloquear ANTES de que el backend tenga el
-- motor dejaria tiles que aceptan la apuesta y luego no saben jugarla.
-- ============================================================

-- La rueda baja de 50x a 20x.
--
-- No es un recorte arbitrario: con 50 casillas, UNA sola de 50x aporta 1.00 al
-- retorno — mas que el RTP entero de 0.96— y no quedaria nada para las demas.
-- Sostener un 50x honesto pedia 60+ casillas con casi todas en cero, que es
-- una rueda peor de jugar. El motor reparte 32 ceros, 10 de 1x, 5 de 2x,
-- 2 de 4x y 1 de 20x: suma 48.00 sobre 50 casillas = 0.9600 exacto.
UPDATE [dbo].[arcadeGames]
SET maxMultiplier = 20.00, updated_at = GETUTCDATE()
WHERE gameKey = 'wheel' AND maxMultiplier <> 20.00;
GO

-- Tope real de cada motor, para que el cinturon de seguridad de _payout_for()
-- no recorte un premio legitimo (como pasaba al doblar en blackjack).
UPDATE [dbo].[arcadeGames] SET maxMultiplier = 20.00, updated_at = GETUTCDATE()
WHERE gameKey = 'higherlower' AND maxMultiplier <> 20.00;
GO
UPDATE [dbo].[arcadeGames] SET maxMultiplier = 24.00, updated_at = GETUTCDATE()
WHERE gameKey = 'mines' AND maxMultiplier <> 24.00;
GO
UPDATE [dbo].[arcadeGames] SET maxMultiplier = 3.00, updated_at = GETUTCDATE()
WHERE gameKey = 'penalty' AND maxMultiplier <> 3.00;
GO
UPDATE [dbo].[arcadeGames] SET maxMultiplier = 10.00, updated_at = GETUTCDATE()
WHERE gameKey = 'bowling' AND maxMultiplier <> 10.00;
GO

-- Dados: el pago sube al bajar la probabilidad; con umbral 4 el tope real es
-- 0.97 * 100/4 = 24.25.
UPDATE [dbo].[arcadeGames] SET maxMultiplier = 24.25, updated_at = GETUTCDATE()
WHERE gameKey = 'dice' AND maxMultiplier <> 24.25;
GO

-- Volado: moneda justa que paga 1.96x (2 x 0.98).
UPDATE [dbo].[arcadeGames] SET maxMultiplier = 1.96, updated_at = GETUTCDATE()
WHERE gameKey = 'coinflip' AND maxMultiplier <> 1.96;
GO

-- Desbloquear.
UPDATE [dbo].[arcadeGames]
SET comingSoon = '0', updated_at = GETUTCDATE()
WHERE gameKey IN ('bowling','dice','coinflip','higherlower','mines','wheel','scratch','penalty')
  AND comingSoon <> '0';
GO
