/* -----------------------------------------------------------------------------------------
                                1. LIMPIEZA INICIAL DE DATOS
    -----------------------------------------------------------------------------------------  */
USE [BD_SEGUROS];
GO

-- Limpiar datos previos para evitar duplicados en pruebas
DELETE FROM [BD_SEGUROS].[dbo].[BD_CLIENTE] WHERE MES_CORTE >= 201011;
DELETE FROM [BD_SEGUROS].[dbo].[BD_TB_SEGURO] WHERE MES_CORTE >= 201011;
DELETE FROM [BD_SEGUROS].[dbo].[TB_PRODUCTOS_FINANCIEROS] WHERE MES_CORTE >= 201011;
GO

/* -----------------------------------------------------------------------------------------
                        2. CREACIÓN DE TABLAS AUXILIARES (STAGING)
    -----------------------------------------------------------------------------------------  */

IF OBJECT_ID('dbo.BD_CLIENTE_AUX','U') IS NOT NULL DROP TABLE BD_CLIENTE_AUX;
CREATE TABLE BD_CLIENTE_AUX(
	CODIGO VARCHAR(257), AGENCIA VARCHAR(257), SEGMENTO VARCHAR(257),
	MES_CORTE VARCHAR(6), SEXO VARCHAR(257), EDAD VARCHAR(257),
	UBIGEO VARCHAR(257), INGRESO VARCHAR(255), SITUACION VARCHAR(257),
	FECHA_ALTA VARCHAR(255)
);

IF OBJECT_ID('dbo.BD_TB_SEGURO_AUX','U') IS NOT NULL DROP TABLE BD_TB_SEGURO_AUX;
CREATE TABLE BD_TB_SEGURO_AUX(
	CODIGO VARCHAR(50), MES_CORTE VARCHAR(50), cd_subproducto VARCHAR(50),
	cd_canal_venta VARCHAR(50), cd_divisa VARCHAR(50), fh_apertura VARCHAR(50),
	fh_vencimiento VARCHAR(50), im_prima VARCHAR(50), im_capital_aseg VARCHAR(50),
	im_comision VARCHAR(50)
);

IF OBJECT_ID('dbo.TB_PRODUCTOS_FINANCIEROS_AUX','U') IS NOT NULL DROP TABLE TB_PRODUCTOS_FINANCIEROS_AUX;
CREATE TABLE TB_PRODUCTOS_FINANCIEROS_AUX(
	CODIGO VARCHAR(50), MES_CORTE VARCHAR(50), FLGVIP VARCHAR(50),
	FLGVPH VARCHAR(50), FLGTC VARCHAR(50), FLGAHO VARCHAR(50),
	FLGSEG VARCHAR(50), FLGSBS VARCHAR(50)
);
GO

/* -----------------------------------------------------------------------------------------
                        3. TRANSFORMACIÓN E INSERCIÓN (CORE)
    -----------------------------------------------------------------------------------------  */

-- Carga BD_CLIENTE con normalización de UBIGEO y AGENCIA
INSERT INTO BD_CLIENTE
SELECT 
	CODIGO,
	RIGHT('0000' + LTRIM(AGENCIA), 4),
	SEGMENTO,
	MES_CORTE,
	SEXO,
	EDAD,
	CASE 
        WHEN UBIGEO = '' THEN (
			SELECT TOP 1 UBIGEO collate Modern_Spanish_CI_AS FROM [BD_SEGUROS].[dbo].[BD_CLIENTE]
			GROUP BY UBIGEO ORDER BY COUNT(1) DESC
		)
        WHEN LEN(UBIGEO) < 7 THEN CONCAT('0', UBIGEO) 
       	ELSE UBIGEO 
    END AS UBIGEO,
	INGRESO,
	CONVERT(CHAR(1), SITUACION),
	FECHA_ALTA
FROM BD_CLIENTE_AUX;

-- Carga BD_TB_SEGURO con casting numérico
INSERT INTO BD_TB_SEGURO
SELECT
	CODIGO, MES_CORTE,
	RIGHT('0000' + LTRIM(cd_subproducto), 4),
	RIGHT('00' + LTRIM(cd_canal_venta), 2),
	cd_divisa, fh_apertura, fh_vencimiento,
	CONVERT(FLOAT, im_prima), CONVERT(FLOAT, im_capital_aseg), CONVERT(FLOAT, im_comision)
FROM BD_TB_SEGURO_AUX;

-- Carga TB_PRODUCTOS_FINANCIEROS
INSERT INTO TB_PRODUCTOS_FINANCIEROS
SELECT 
	CODIGO, MES_CORTE,
	CONVERT(CHAR(1), FLGVIP), CONVERT(CHAR(1), FLGVPH), CONVERT(CHAR(1), FLGTC),
	CONVERT(CHAR(1), FLGAHO), CONVERT(CHAR(1), FLGSEG), CONVERT(CHAR(1), FLGSBS)
FROM TB_PRODUCTOS_FINANCIEROS_AUX;

-- Limpiar tablas temporales de BD_SEGUROS
DROP TABLE BD_CLIENTE_AUX;
DROP TABLE BD_TB_SEGURO_AUX;
DROP TABLE TB_PRODUCTOS_FINANCIEROS_AUX;
GO

/* -----------------------------------------------------------------------------------------
                        4. DATA WAREHOUSE: ESTRUCTURA Y DIMENSIONES
    -----------------------------------------------------------------------------------------  */

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'DWH_SEGUROS')
	CREATE DATABASE DWH_SEGUROS;
GO

USE DWH_SEGUROS;
GO

-- 4.1 Generación de Dimensiones Dinámicas
-- * Dimension de Agencia
-- * Dimension de Segmento
-- * Dimensin de Ubigeo
-- * Dimension de Tipo de Seguro
DECLARE @Dimensiones TABLE (Nombre NVARCHAR(255), CampoPK NVARCHAR(255), Script NVARCHAR(MAX));
INSERT INTO @Dimensiones VALUES
('DimAgencia','COD_AGENCIA','SELECT * INTO DimAgencia FROM BD_SEGUROS.dbo.BD_AGENCIAS'),
('DimSegmento','COD_SEGMENTO','SELECT * INTO DimSegmento FROM BD_SEGUROS.dbo.BD_SEGMENTO'),
('DimUbigeo','COD_UBIGEO','SELECT * INTO DimUbigeo FROM BD_SEGUROS.dbo.BD_UBIGEO'),
('DimTipoSeguro','CODIGO','SELECT * INTO DimTipoSeguro FROM BD_SEGUROS.dbo.TB_TIPO_SEGURO');

if not exists (select * from INFORMATION_SCHEMA.TABLES where TABLE_NAME in ('DimAgencia', 'DimSegmento', 'DimUbigeo', 'DimTipoSeguro') and TABLE_SCHEMA = 'dbo')
BEGIN
	DECLARE @Nom NVARCHAR(255), @PK NVARCHAR(255), @Cmd NVARCHAR(MAX);
	DECLARE cur CURSOR FOR SELECT Nombre, CampoPK, Script FROM @Dimensiones;
	OPEN cur;
	FETCH NEXT FROM cur INTO @Nom,@PK,@Cmd;
	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF OBJECT_ID(@Nom,'U') IS NULL
		BEGIN
			EXEC (@Cmd);
			EXEC('ALTER TABLE '+@Nom+' ALTER COLUMN '+@PK+' NVARCHAR(255) NOT NULL');
			EXEC('ALTER TABLE '+@Nom+' ADD CONSTRAINT PK_'+@Nom+' PRIMARY KEY ('+@PK+')');
		END
		FETCH NEXT FROM cur INTO @Nom,@PK,@Cmd;
	END
	CLOSE cur; 
	DEALLOCATE cur;

	-- Agregar valores faltantes para 'D_SEGMENTO' y 'D_UBIGEO'
	insert into [DWH_SEGUROS].[dbo].[DimSegmento] values ('999999', 'SEGMENTO FALTANTE EN EMPRESAS', 'EMPRESAS');
	insert into [DWH_SEGUROS].[dbo].[DimUbigeo] values
	('01', '', '', ''),
	('0810003', '', '', ''),
	('0811000', '', '', ''),
	('0810006', '', '', '');
END

-- 4.2 Dimensiones Estáticas (Catálogos)

-- Dimension Sexo
IF OBJECT_ID('DimSexo','U') IS NULL
BEGIN
	CREATE TABLE DimSexo (COD_SEXO CHAR(1) PRIMARY KEY, DES_SEXO VARCHAR(50));
	INSERT INTO DimSexo VALUES ('M','MASCULINO'),('F','FEMENINO'),('X','EMPRESA');
END

-- Dimension Situacion
IF OBJECT_ID('DimSituacion','U') IS NULL
BEGIN
	CREATE TABLE DimSituacion (COD_SITUACION CHAR(1) PRIMARY KEY, DESCRIPCION VARCHAR(50));
	INSERT INTO DimSituacion VALUES ('A','EMPLEADO FIJO'),('C','EMPLEADO CONTRATADO'),('P','PENSIONISTA');
END

-- Dimension de Canal de Venta
IF OBJECT_ID('DimCanalVenta','U') IS NULL
BEGIN
	CREATE TABLE DimCanalVenta (COD_CANAL VARCHAR(2) PRIMARY KEY, DESCRIPCION VARCHAR(50));
	INSERT INTO DimCanalVenta VALUES ('01','AGENCIAS'),('02','DIGITAL'),('03','TELEMARKETING');
END

-- Dimnesion de Rango de Edad
IF OBJECT_ID('DimRangoEdad','U') IS NULL
BEGIN
	CREATE TABLE DimRangoEdad (COD_RGEDAD INT PRIMARY KEY, RANGO_EDAD VARCHAR(50));
	INSERT INTO DimRangoEdad VALUES 
	(1,'1. SIN EDAD'),(2,'2. HASTA 25 AÑOS'),(3,'3. DE 25 A 30 AÑOS'),(4,'4. DE 30 A 35 AÑOS'),
	(5,'5. DE 35 A 40 AÑOS'),(6,'6. DE 40 A 45 AÑOS'),(7,'7. DE 45 A 50 AÑOS'),(8,'8. DE 50 A 55 AÑOS'),
	(9,'9. DE 55 A 60 AÑOS'),(10,'10. DE 60 A 65 AÑOS'),(11,'11. MÁS DE 65 AÑOS');
END

-- Dimension de rango de ingreso
IF OBJECT_ID('DimRangoIngreso','U') IS NULL
BEGIN
	CREATE TABLE DimRangoIngreso (COD_RGINGRESO INT PRIMARY KEY, RANGO_INGRESO VARCHAR(50));
	INSERT INTO DimRangoIngreso VALUES
	(1,'1. SIN INGRESO'),(2,'2. HASTA 1000 SOLES'),(3,'3. DE 1000 A 2500 SOLES'),
	(4,'4. DE 2500 A 3500 SOLES'),(5,'5. DE 3500 A 7000 SOLES'),(6,'6. DE 7000 A 10000 SOLES'),
	(7,'7. DE 10,000 A MÁS');
END

-- Dimension de Fecha de Stock
IF OBJECT_ID('DimFechaStock','U') IS NULL
BEGIN
	CREATE TABLE DimFechaStock (MES_PROCESO VARCHAR(6) PRIMARY KEY, ANIO INT, CODMES INT, MES VARCHAR(10));
	INSERT INTO DimFechaStock VALUES 
		('201001', 2010, 1, '01-ene'),
		('201002', 2010, 2, '02-feb'),
		('201003', 2010, 3, '03-mar'),
		('201004', 2010, 4, '04-abr'),
		('201005', 2010, 5, '05-may'),
		('201006', 2010, 6, '06-jun'),
		('201007', 2010, 7, '07-jul'),
		('201008', 2010, 8, '08-ago'),
		('201009', 2010, 9, '09-sep'),
		('201010', 2010, 10, '10-oct'),
		('201011', 2010, 11, '11-nov'),
		('201012', 2010, 12, '12-dic'),
		('201101', 2011, 1, '01-ene'),
		('201102', 2011, 2, '02-feb'),
		('201103', 2011, 3, '03-mar'),
		('201104', 2011, 4, '04-abr'),
		('201105', 2011, 5, '05-may'),
		('201106', 2011, 6, '06-jun'),
		('201107', 2011, 7, '07-jul'),
		('201108', 2011, 8, '08-ago'),
		('201109', 2011, 9, '09-sep'),
		('201110', 2011, 10, '10-oct'),
		('201111', 2011, 11, '11-nov'),
		('201112', 2011, 12, '12-dic');
END
GO


/* -----------------------------------------------------------------------------------------
                                5. CONSTRUCCIÓN DE LA FACT TABLE
    -----------------------------------------------------------------------------------------  */

-- Auxiliar 1: Clientes y Cálculo de Rangos de Edad e Ingresos
DROP TABLE IF EXISTS [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_1];
SELECT
	CODIGO AS COD_CLIENTE, 
	AGENCIA, 
	SEGMENTO, 
	MES_CORTE, 
	SEXO, 
	CONVERT(INT,LTRIM(RTRIM(EDAD))) AS EDAD, 
	UBIGEO, 
	INGRESO, 
	SITUACION,
	LTRIM(RTRIM(FECHA_ALTA)) AS FECHA_ALTA,
	CASE
		WHEN EDAD < 1 OR EDAD IS NULL THEN 1
		WHEN EDAD <= 25 THEN 2
		WHEN EDAD <= 30 THEN 3
		WHEN EDAD <= 35 THEN 4
		WHEN EDAD <= 40 THEN 5
		WHEN EDAD <= 45 THEN 6
		WHEN EDAD <= 50 THEN 7
		WHEN EDAD <= 55 THEN 8
		WHEN EDAD <= 60 THEN 9
		WHEN EDAD <= 65 THEN 10
		ELSE 11
	END AS RGEDAD,
	CASE
		WHEN INGRESO = 0 OR INGRESO IS NULL THEN 1
		WHEN INGRESO <= 1000 THEN 2
		WHEN INGRESO <= 2500 THEN 3
        WHEN INGRESO <= 3500 THEN 4
        WHEN INGRESO <= 7000 THEN 5
        WHEN INGRESO <= 10000 THEN 6
		ELSE 7
	END AS RGINGRESO
INTO [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_1]
FROM [BD_SEGUROS].[dbo].[BD_CLIENTE]
ORDER BY CODIGO, MES_CORTE;

-- Auxiliar 2: Seguros Agregados
DROP TABLE IF EXISTS [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_2];
SELECT 
    CODIGO as COD_CLIENTE, 
    MES_CORTE, 
    cd_subproducto as TIPO_SEGURO,
    cd_canal_venta as CANAL, 
    cd_divisa as DIVISA, 
    ltrim(rtrim(fh_apertura)) as FECHA_APERTURA, 
    ltrim(rtrim(fh_vencimiento)) as FECHA_VENCIMIENTO,
	sum(im_prima) as TOTAL_PRIMA, 
	sum(im_capital_aseg) as TOTAL_CAPITAL_ASEGURADO, 
	sum(im_comision) as TOTAL_COMISION
INTO [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_2]
FROM [BD_SEGUROS].[dbo].[BD_TB_SEGURO]
GROUP BY CODIGO, MES_CORTE, cd_subproducto, cd_canal_venta, cd_divisa, ltrim(rtrim(fh_apertura)), ltrim(rtrim(fh_vencimiento));
GO

-- Auxiliar 3: Productos Financieros
DROP TABLE IF EXISTS [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_3];
SELECT CODIGO AS COD_CLIENTE, MES_CORTE, FLGVIP, FLGVPH, FLGTC, FLGAHO, FLGSEG, FLGSBS
INTO [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_3]
FROM [BD_SEGUROS].[dbo].[TB_PRODUCTOS_FINANCIEROS];
GO

-- FACT_SEGUROS Final
DROP TABLE IF EXISTS [DWH_SEGUROS].[dbo].[FACT_SEGUROS];
CREATE TABLE [DWH_SEGUROS].[dbo].[FACT_SEGUROS] (
    COD_CLIENTE varchar(257) not null,
    AGENCIA nvarchar(255) not null,
	SEGMENTO nvarchar(255) not null,
	MES_CORTE varchar(6) not null,
	SEXO char(1) not null,
	EDAD int not null,
	UBIGEO nvarchar(255) not null,
	INGRESO float not null,
	SITUACION char(1) not null,
	FECHA_ALTA varchar(255) not null,
	RGEDAD int not null,
	RGINGRESO int not null,
	TIPO_SEGURO nvarchar(255) not null,
	CANAL varchar(2) not null,
    DIVISA varchar(255) not null, 
    FECHA_APERTURA varchar(255) not null,  
    FECHA_VENCIMIENTO  varchar(255) null, 
	TOTAL_PRIMA float not null, 
	TOTAL_CAPITAL_ASEGURADO float not null, 
	TOTAL_COMISION float not null,
	FLGVIP varchar(1) not null,
	FLGVPH varchar(1) not null, 
	FLGTC varchar(1) not null, 
	FLGAHO varchar(1) not null,
	FLGSEG varchar(1) not null,
	FLGSBS  varchar(1) not null
);
INSERT INTO [DWH_SEGUROS].[dbo].[FACT_SEGUROS]
SELECT
    A.COD_CLIENTE, 
    AGENCIA, 
    SEGMENTO, 
    A.MES_CORTE, 
    SEXO, 
    EDAD, 
    UBIGEO, 
    INGRESO, 
    SITUACION, 
    FECHA_ALTA,
    RGEDAD,
    RGINGRESO,
    TIPO_SEGURO, 
    CANAL, 
    DIVISA, 
    FECHA_APERTURA, 
    FECHA_VENCIMIENTO, 
	TOTAL_PRIMA, 
	TOTAL_CAPITAL_ASEGURADO, 
	TOTAL_COMISION,
	FLGVIP,
	FLGVPH,
	FLGTC,
	FLGAHO,
	FLGSEG,
	FLGSBS
FROM [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_1] A
INNER JOIN [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_2] B 
	ON A.COD_CLIENTE = B.COD_CLIENTE 
	AND A.MES_CORTE = B.MES_CORTE
INNER JOIN [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_3] C 
	ON A.COD_CLIENTE = C.COD_CLIENTE 
	AND A.MES_CORTE = C.MES_CORTE;

-- Limpieza de auxiliares FACT
drop table if exists [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_1];
drop table if exists [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_2];
drop table if exists [DWH_SEGUROS].[dbo].[FACT_SEGUROS_AUX_3];
GO

/* -----------------------------------------------------------------------------------------
                                6. ÍNDICES Y LLAVES FORÁNEAS
    -----------------------------------------------------------------------------------------  */
CREATE INDEX INDEX_FACT_SEGUROS ON  [DWH_SEGUROS].[dbo].[FACT_SEGUROS](COD_CLIENTE, MES_CORTE);

ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Agencia FOREIGN KEY (AGENCIA) REFERENCES DimAgencia(COD_AGENCIA);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Segmento FOREIGN KEY (SEGMENTO) REFERENCES DimSegmento(COD_SEGMENTO);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Mes_Corte FOREIGN KEY (MES_CORTE) REFERENCES DimFechaStock(MES_PROCESO);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Sexo FOREIGN KEY (SEXO) REFERENCES DimSexo(COD_SEXO);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Ubigeo FOREIGN KEY (UBIGEO) REFERENCES DimUbigeo(COD_UBIGEO);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Situacion FOREIGN KEY (SITUACION) REFERENCES DimSituacion(COD_SITUACION);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Rango_Edad FOREIGN KEY (RGEDAD) REFERENCES DimRangoEdad(COD_RGEDAD);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Rango_Ingreso FOREIGN KEY (RGINGRESO) REFERENCES DimRangoIngreso(COD_RGINGRESO);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Tipo_Seguro FOREIGN KEY (TIPO_SEGURO) REFERENCES DimTipoSeguro(CODIGO);
ALTER TABLE  [DWH_SEGUROS].[dbo].[FACT_SEGUROS] ADD CONSTRAINT FK_Canal FOREIGN KEY (CANAL) REFERENCES DimCanalVenta(COD_CANAL);
GO

