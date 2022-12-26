SET NAMES 'utf8mb4';

CREATE DATABASE yield
	CHARACTER SET utf8mb4
	COLLATE utf8mb4_0900_ai_ci;

USE yield;

-- 
-- Установить режим SQL (SQL mode)
-- 
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;


DROP PROCEDURE IF EXISTS yield_test;

DROP PROCEDURE IF EXISTS yield_calc;

DELIMITER $$

--
-- Создать процедуру `yield_calc`
--
CREATE 
	DEFINER = 'root'@'localhost'
PROCEDURE yield_calc()
BEGIN

  # Расчёт доходности в процентах
  # Можно применять как при расчёте по одной инвестиции,
  # так и по одному клиенту в целом

  # Процедура выдаёт в качестве решения процент ГОДОВОЙ доходности.
  # Поэтому не следёет применять процедуру для расчёта за высокодоходный период несколько дней.
  # Потому что даже 10% дневной доходности, выраженные в процентах годовых представляет из себя огромное число.

  # Автор
  #   2020-09-12  Nik Mant

  DECLARE _yield_day_mult          # коэфициент, на который увеличивается капитал счёта каждый день
        , _yield_day_perc          # процент,    на который увеличивается капитал счёта каждый день
        , _yield_year_mult         # коэфициент, на который увеличивается капитал счёта каждый год
        , _yield_year_perc         # процент,    на который увеличивается капитал счёта каждый год
        double;
  DECLARE _yield_day_mult_min      # ограничение по  минимальному значению для _yield_day_mult
        , _yield_day_mult_max      # ограничение по максимальному значению для _yield_day_mult
        , _yield_year_perc_min     # ограничение по  минимальному значению для _yield_year_perc
        , _yield_year_perc_max     # ограничение по максимальному значению для _yield_year_perc
        double;
  DECLARE _profit_iter             # сумма дохода с учётом изменцивой стоимости денег по выбранному в итерации проценту
        , _profit_real             # сумма (доход), в денежном выражении, заработанная за период
        double;
  DECLARE _iteration               # номер итерации для цикла подбора решения
        int;
  DECLARE _start_date              # дата начала     расчётного периода доходности
        , _end_date                # дата завершения расчётного периода доходности
        date;

  # Узнаю дату первой и последней инвестиции
  SELECT MIN(ddate), MAX(ddate), -SUM(amount)
  FROM   invest_transfer
  INTO  _start_date,  _end_date, _profit_real;

  # Выбираю минимальный и максималный процент за год (диапазон для поиска решения)
  IF (_profit_real >= 0) THEN
    SET _yield_year_perc_min = 0;
    SET _yield_year_perc_max = 1000*1000*1000*1000  + 10*1000*1000;
  ELSE                          
    SET _yield_year_perc_min = -99.99999;
    SET _yield_year_perc_max = 0;
  END IF;

  # Расчитываю минимальные и максималные приросты за день (диапазон для поиска решения)
  SET _yield_day_mult_min = POWER(1+_yield_year_perc_min/100, 1/365);
  SET _yield_day_mult_max = POWER(1+_yield_year_perc_max/100, 1/365);

  # Инициирую переменные
  SET _yield_day_mult = 1;
  SET _iteration = 0;
  SET _profit_iter = _profit_real;

  # Цикл для поиска решения
  # Итерационно ищу неизвестную _yield_day_mult
  REPEAT

    # Считаю уточняющее новое значение _yield_day_mult
    # между двумя концами интервала решения
    # А также сужаю сам интервал,
    # используя среднеквадратичные приближения к решению
    IF _profit_iter>0 THEN
      SET _yield_day_mult_min = _yield_day_mult;
      SET _yield_day_mult = SQRT(_yield_day_mult)*SQRT(_yield_day_mult_max);
    ELSE
      SET _yield_day_mult_max = _yield_day_mult;
      SET _yield_day_mult = SQRT(_yield_day_mult)*SQRT(_yield_day_mult_min);
    END IF;

    SET _profit_iter = 
         (
         SELECT -SUM(amount*POWER(_yield_day_mult, DATEDIFF(_end_date, ddate)))
         FROM invest_transfer
         );
    
    SET _iteration = _iteration + 1;

  UNTIL (_iteration>200) OR (ABS(_profit_iter)<0.005) OR (_yield_day_mult=_yield_day_mult_max) OR (_yield_day_mult=_yield_day_mult_min) END REPEAT;

  # Перевожу в человеко-понятные проценты
  SET _yield_day_perc  = ROUND(_yield_day_mult*100-100, 2);
  SET _yield_year_perc = ROUND(LEAST( 1000*1000*1000*1000, POWER(_yield_day_mult,365)*100-100 ), 2);

  # Вывожу результат
  # в поле _yield_year_perc - искомый процент доходности в годовых
  SELECT _profit_real, _yield_year_perc, _yield_day_perc, _yield_day_mult, _iteration, _profit_iter;

END
$$

--
-- Создать процедуру `yield_test`
--
CREATE 
	DEFINER = 'root'@'localhost'
PROCEDURE yield_test()
BEGIN

  # Если эта временная таблица уже есть, удаляю её
  DROP TEMPORARY TABLE IF EXISTS invest_transfer;

  # Это временная таблица, на примере которой я веду расчёт
  # С реальным счётом, в качестве последнего значения необходимо
  # брать чистое эквити счёта на момент завершения периода

  /*
  # Пример №1 (простейший банковский депозит на год)
  CREATE TEMPORARY TABLE invest_transfer
  SELECT  '2020-01-01' AS ddate, +100000 AS amount
    UNION
  SELECT  '2020-12-31' AS ddate, -107000 AS amount
  ;
  */

  /*
  # Пример №2 (банковский депозит на год, с пополнением в середине)
  CREATE TEMPORARY TABLE invest_transfer
  SELECT  '2020-01-01' AS ddate, +10000 AS amount
    UNION
  SELECT  '2020-07-01' AS ddate, +10000 AS amount
    UNION
  SELECT  '2020-12-31' AS ddate, -22000 AS amount
  ;
  */
  
  /*
  # Пример №3 
  #   * непредсказуемые пополнения и выводы инвестора внутри периода оценки доходности счёта
  #   * период не равен году
  #   * в середине периода счёт уходил в овердрафт
  CREATE TEMPORARY TABLE invest_transfer
  SELECT  '2020-02-04' AS ddate, +111735 AS amount
    UNION
  SELECT  '2020-03-03' AS ddate, +40500 AS amount
    UNION
  SELECT  '2020-05-25' AS ddate, -130000 AS amount
    UNION
  SELECT 	'2020-06-15' AS ddate, -50000 AS amount
    UNION
  SELECT  '2020-07-30' AS ddate, +1250000 AS amount
    UNION
  SELECT  '2020-12-31' AS ddate, -1284343 AS amount
  ;
  */

/*
  CREATE TEMPORARY TABLE invest_transfer
  SELECT  '2020-01-01' AS ddate, +  1000 AS amount
    UNION
  SELECT  '2020-07-01' AS ddate, +100000 AS amount
    UNION
  SELECT  '2020-12-31' AS ddate, -100000 AS amount
  ;
*/

  CREATE TEMPORARY TABLE invest_transfer
  SELECT  '2020-01-01' AS ddate, 1 AS amount
  union
  SELECT  '2020-07-01' AS ddate, -100 AS amount
  union
  SELECT  '2020-07-02' AS ddate, 20000 AS amount
  union
  SELECT  '2020-12-01' AS ddate, -19900 AS amount
;

  # Рассчитываю процент доходности по этим данным
  CALL yield_calc();

END
$$

DELIMITER ;

-- 
-- Восстановить предыдущий режим SQL (SQL mode)
--
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;

-- 
-- Включение внешних ключей
-- 
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;