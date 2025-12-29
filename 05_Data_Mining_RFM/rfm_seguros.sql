
/*  -----------------------------------------------------------------------------------------
											RFM
	-----------------------------------------------------------------------------------------  */
 ---------------------------------------- [RFM_BASE] ----------------------------------------
 IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'RFM_SEGUROS')
	CREATE DATABASE RFM_SEGUROS
GO

USE RFM_SEGUROS
GO

 drop table if exists [RFM_SEGUROS].[dbo].[RFM_BASE];
 SELECT
    COD_CLIENTE,
    DATEDIFF(DAY, CONVERT(date, MAX(FECHA_ALTA), 103), '2011-01-01') AS RECENCIA,
    COUNT(MES_CORTE) AS FRECUENCIA,
    ROUND(AVG(
		CASE
			WHEN DIVISA = 'USD' THEN TOTAL_PRIMA * 3.79
			WHEN DIVISA = 'PEN' THEN TOTAL_PRIMA
		END),2) AS MONTO
INTO [RFM_SEGUROS].[dbo].[RFM_BASE]
FROM [DWH_SEGUROS].[dbo].[FACT_SEGUROS]
WHERE SEXO IN ('M', 'F')
GROUP BY COD_CLIENTE

 --------------------------------------- [RFM_SCORES] ---------------------------------------
 drop table if exists [RFM_SEGUROS].[dbo].[RFM_SCORES];
 drop table if exists [RFM_SEGUROS].[dbo].[RFM_SCORES];
select 
    COD_CLIENTE,
    RECENCIA,
    FRECUENCIA,
    MONTO,
    ntile(5) over (order by RECENCIA desc) as R_SCORE, -- Puntaje de Recencia (1-6)
    ntile(5) over (order by FRECUENCIA asc) as F_SCORE, -- Puntaje de Frecuencia (1-6)
    ntile(5) over (order by MONTO asc) as M_SCORE -- Puntaje de Valor Monetario (1-6)
into [RFM_SEGUROS].[dbo].[RFM_SCORES]
from [RFM_SEGUROS].[dbo].[RFM_BASE];

 ------------------------------------ [RFM_SCORES_FINAL] ------------------------------------
drop table if exists [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL];
select 
    COD_CLIENTE,
    RECENCIA,
    FRECUENCIA,
    MONTO,
    (R_SCORE * 1 + F_SCORE * 2 + M_SCORE * 3) as Score, 
	case
        when (R_SCORE * 1 + F_SCORE * 2 + M_SCORE * 3) < 20 then '1. Bajo'
        when (R_SCORE * 1 + F_SCORE * 2 + M_SCORE * 3) < 27 then '2. Medio'
        else '3. Alto'
    end as SEGMENTO  -- Puntaje RFM combinado
into [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL]
from [RFM_SEGUROS].[dbo].[RFM_SCORES]
order by COD_CLIENTE;

-- Promedio por Segemento
select
	SEGMENTO,
	count(COD_CLIENTE) as Clientes,
	cast(round((count(COD_CLIENTE) * 100.0 / (select count(*) from [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL])), 2) as float) as Porc_Clientes,
	avg(cast(RECENCIA as int)) as RECENCIA,
	avg(FRECUENCIA) as FRECUENCIA,
	round(avg(MONTO), 2) as MONTO
from [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL]
group by SEGMENTO
order by 1 asc;

-- Promedio general
select
	avg(cast(RECENCIA as int)) as RECENCIA,
	avg(FRECUENCIA) as FRECUENCIA,
	round(avg(MONTO), 2) as MONTO
from [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL]


/*  -----------------------------------------------------------------------------------------
										RFM_MEDIDAS
	-----------------------------------------------------------------------------------------  */
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_1];
with ULT_MES_CORTE_X_CLIENTE as (
    select
		COD_CLIENTE,
		max(MES_CORTE) as MES_CORTE
	from [DWH_SEGUROS].[dbo].[FACT_SEGUROS]
	where SEXO in ('M', 'F')
	group by COD_CLIENTE
)
select distinct
	A.COD_CLIENTE,
	EDAD,
	RANGO_EDAD,
	case
		when EDAD between 12 and 27 then '6. Z'
		when EDAD between 28 and 43 then '5. Millennial'
		when EDAD between 44 and 59 then '4. X'
		when EDAD between 60 and 78 then '3. Baby Boomers'
		when EDAD between 79 and 96 then '2. Silenciosa'
		when EDAD >= 97 then '1. G.I.'
		else '0. Desconocida'
	end as GENERACION,
	SEXO,
	UBIGEO,
	DEPARTAMENTO,
	PROVINCIA,
	DISTRITO,
	E.DESCRIPCION as SITUACION,
	INGRESO,
	RANGO_INGRESO,
	AGENCIA,
	SEGMENTO,
	FLGVIP,
	FLGVPH,
	FLGTC,
	FLGAHO,
	FLGSEG,
	FLGSBS
into [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_1]
from [DWH_SEGUROS].[dbo].[FACT_SEGUROS] A
join ULT_MES_CORTE_X_CLIENTE B on A.COD_CLIENTE = B.COD_CLIENTE
join [DWH_SEGUROS].[dbo].[DimUbigeo] C on A.UBIGEO = C.COD_UBIGEO
join [DWH_SEGUROS].[dbo].[DimRangoEdad] D on A.RGEDAD = D.COD_RGEDAD
join [DWH_SEGUROS].[dbo].[DimSituacion] E on A.SITUACION = E.COD_SITUACION
join [DWH_SEGUROS].[dbo].[DimRangoIngreso] F on A.RGINGRESO = F.COD_RGINGRESO
where A.MES_CORTE = B.MES_CORTE
order by A.COD_CLIENTE;

 ------------------------------------ [RFM_MEDIDAS_AUX_2] -----------------------------------
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_2];
with ULT_MES_CORTE_X_CLIENTE as (
    select
		COD_CLIENTE,
		max(MES_CORTE) as MES_CORTE
	from [DWH_SEGUROS].[dbo].[FACT_SEGUROS]
	where SEXO in ('M', 'F')
	group by COD_CLIENTE
)
select distinct
    A.COD_CLIENTE,
    round(sum(
        case 
            when A.DIVISA = 'USD' then A.TOTAL_PRIMA * 3.79
            when A.DIVISA = 'PEN' then A.TOTAL_PRIMA
            else 0
        end
    ), 2) as TOTAL_PRIMA,
    round(sum(
        case 
            when A.DIVISA = 'USD' then A.TOTAL_CAPITAL_asEGURADO * 3.79
            when A.DIVISA = 'PEN' then A.TOTAL_CAPITAL_asEGURADO
            else 0
        end
    ), 2) as TOTAL_CAPITAL_ASEGURADO,
    round(sum(
        case 
            when A.DIVISA = 'USD' then A.TOTAL_COMISION * 3.79
            when A.DIVISA = 'PEN' then A.TOTAL_COMISION
            else 0
        end
    ), 2) as TOTAL_COMISION
into [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_2]
from [DWH_SEGUROS].[dbo].[FACT_SEGUROS] A
join ULT_MES_CORTE_X_CLIENTE B on A.COD_CLIENTE = B.COD_CLIENTE
where A.MES_CORTE = B.MES_CORTE
group by A.COD_CLIENTE
order by A.COD_CLIENTE;

 ------------------------------------ [RFM_MEDIDAS_AUX_3] -----------------------------------
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_3];
with ULT_MES_CORTE_X_CLIENTE as (
    select
		COD_CLIENTE,
		max(MES_CORTE) as MES_CORTE
	from [DWH_SEGUROS].[dbo].[FACT_SEGUROS]
	where SEXO in ('M', 'F')
	group by COD_CLIENTE
),
CANAL_PREFERIDO as (
    select distinct
        A.COD_CLIENTE,
        first_value(A.CANAL) over (
            partition by A.COD_CLIENTE
            order by case when A.DIVISA = 'PEN' then 0 else 1 end, A.MES_CORTE desc
        ) as CANAL
    from [DWH_SEGUROS].[dbo].[FACT_SEGUROS] A
    join ULT_MES_CORTE_X_CLIENTE B on A.COD_CLIENTE = B.COD_CLIENTE
    where A.MES_CORTE = B.MES_CORTE
)
select
    A.COD_CLIENTE,
    D.DESCRIPCION as CANAL
into [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_3]
from CANAL_PREFERIDO C
join ULT_MES_CORTE_X_CLIENTE A on A.COD_CLIENTE = C.COD_CLIENTE
join [DWH_SEGUROS].[dbo].[DimCanalVenta] D on C.CANAL = D.COD_CANAL
order by A.COD_CLIENTE;

 ------------------------------------ [RFM_MEDIDAS_FINAL] -----------------------------------
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_FINAL];
select
	A.COD_CLIENTE,
	EDAD,
	RANGO_EDAD,
	GENERACION,
	SEXO,
	UBIGEO,
	DEPARTAMENTO,
	PROVINCIA,
	DISTRITO,
	SITUACION,
	INGRESO,
	RANGO_INGRESO,
	CANAL,
	AGENCIA,
	SEGMENTO,
	TOTAL_PRIMA,
	TOTAL_CAPITAL_ASEGURADO,
	TOTAL_COMISION,
	FLGVIP,
	FLGVPH,
	FLGTC,
	FLGAHO,
	FLGSEG,
	FLGSBS
into [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_FINAL]
from [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_1] A
join [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_2] B on A.COD_CLIENTE = B.COD_CLIENTE
join [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_3] C on A.COD_CLIENTE = C.COD_CLIENTE;

/*  -----------------------------------------------------------------------------------------
										RFM_FINAL
	-----------------------------------------------------------------------------------------  */
drop table if exists [RFM_SEGUROS].[dbo].[RFM_FINAL];
select
	A.COD_CLIENTE,
    RECENCIA,
    FRECUENCIA,
    MONTO,
	A.SEGMENTO as SEGMENTO_RFM,
	EDAD,
	RANGO_EDAD,
	GENERACION,
	SEXO,
	UBIGEO,
	DEPARTAMENTO,
	PROVINCIA,
	DISTRITO,
	SITUACION,
	INGRESO,
	RANGO_INGRESO,
	CANAL,
	AGENCIA,
	B.SEGMENTO as SEGMENTO,
	TOTAL_PRIMA,
	TOTAL_CAPITAL_ASEGURADO,
	TOTAL_COMISION,
	FLGVIP,
	FLGVPH,
	FLGTC,
	FLGAHO,
	FLGSEG,
	FLGSBS
into [RFM_SEGUROS].[dbo].[RFM_FINAL]
from [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL] A
join [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_FINAL] B on A.COD_CLIENTE = B.COD_CLIENTE;

-- select * from [RFM_SEGUROS].[dbo].[RFM_FINAL];

drop table if exists [RFM_SEGUROS].[dbo].[RFM_BASE];
drop table if exists [RFM_SEGUROS].[dbo].[RFM_SCORES];
drop table if exists [RFM_SEGUROS].[dbo].[RFM_SCORES_FINAL];
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_1];
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_2];
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_AUX_3];
drop table if exists [RFM_SEGUROS].[dbo].[RFM_MEDIDAS_FINAL];
