CREATE SCHEMA IF NOT EXISTS sato;

CREATE TABLE IF NOT EXISTS sato.server
(
	id text NOT NULL,
	host text NOT NULL,
	port smallint NOT NULL,
	dpi smallint NOT NULL,
	maxlabelheight integer NOT NULL,
	maxlabelwidth integer NOT NULL,	
	minfeed integer NOT NULL,
	maxfeed integer NOT NULL,
	minbackfeed integer NOT NULL,
	maxbackfeed integer NOT NULL,
	maxvert integer NOT NULL,
	maxhorz integer NOT NULL,	
	CONSTRAINT "/*server: id must be unique*/" PRIMARY KEY (id)
)
WITH (OIDS=FALSE);

CREATE OR REPLACE FUNCTION sato.helper_mmdot(i_mm numeric, i_dpi smallint)
RETURNS integer AS $BODY$ SELECT ceil(($1 * $2)/25.4)::integer; $BODY$ LANGUAGE sql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.helper_mmdot(numeric, smallint) FROM public;

CREATE OR REPLACE FUNCTION sato.control_qty(i_qty integer)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"qty",
		"arg": num
		}*/	
	_MAXQTY integer:=999999;
	_ESC text:='1B';
BEGIN
	IF i_qty > _MAXQTY THEN
		RAISE EXCEPTION '/*qty command argument is out of range*/';
	END IF;
	RETURN _ESC || encode(('Q' || i_qty::text)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.control_qty(integer) FROM public;

CREATE OR REPLACE FUNCTION sato.position_vert(i_dpi smallint, i_max integer, i_pos numeric)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"y",
		"arg": mm
		}*/	
	_dot integer;	
	_ESC text:='1B';
BEGIN
	_dot:=sato.helper_mmdot(i_pos, i_dpi);
	IF _dot > i_max THEN
		RAISE EXCEPTION '/*vertical position is out of range*/';
	END IF;
	RETURN _ESC || encode(('V' || _dot::text)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.position_vert(smallint, integer, numeric) FROM public;

CREATE OR REPLACE FUNCTION sato.position_horz(i_dpi smallint, i_max integer, i_pos numeric)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"x",
		"arg": mm
		}*/	
	_dot integer;	
	_ESC text:='1B';
BEGIN
	_dot:=sato.helper_mmdot(i_pos, i_dpi);
	IF _dot > i_max THEN
		RAISE EXCEPTION '/*horizontal position is out of range*/';
	END IF;
	RETURN _ESC || encode(('H' || _dot::text)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.position_horz(smallint, integer, numeric) FROM public;

CREATE OR REPLACE FUNCTION sato.position_origin(i_dpi smallint, i_vertmax integer, i_horzmax integer, j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"origin",
		"arg":{"y": mm, "x": mm}
		}*/	
	_t text;
	_int integer;
	_d text:=''::text;		
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid origin command argument*/';
	END IF;

	_t:=j_arg->>'y';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid origin command argument, y is not found*/';
	END IF;		
	_d:=_d || sato.position_vert(i_dpi, i_vertmax, _t::numeric);
	
	_t:=j_arg->>'x';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid origin command argument, x is not found*/';
	END IF;		
	RETURN _d || sato.position_horz(i_dpi, i_horzmax, _t::numeric);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.position_origin(smallint, integer, integer, json) FROM public;

CREATE OR REPLACE FUNCTION sato.intel_feed(i_dpi smallint, i_min integer, i_max integer, j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"feed",
		"arg":{"height": mm, "qty": num}
		}*/	
	_t text;
	_htdot integer;
	_qty integer;
	_feed integer;
	_d text:=''::text;
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid feed command argument*/';
	END IF;

	_t:=j_arg->>'height';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid feed command argument, height is not found*/';
	END IF;	
	_htdot:=sato.helper_mmdot(_t::numeric, i_dpi);

	_t:=j_arg->>'qty';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid feed command argument, qty is not found*/';
	END IF;	
	_qty:=_t::numeric;

	_feed:=_htdot * _qty;
	IF _feed<i_min OR _feed>i_max THEN
		RAISE EXCEPTION '/*invalid feed command argument, feed length is out of range/';
	END IF;

	RETURN _ESC || encode(('IK0,' || (_htdot*_qty)::text)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.intel_feed(smallint, integer, integer, json) FROM public;

CREATE OR REPLACE FUNCTION sato.intel_backfeed(i_dpi smallint, i_min integer, i_max integer, j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"backfeed",
		"arg":{"height": mm, "qty": num}
		}*/	
	_t text;
	_htdot integer;
	_qty integer;
	_feed integer;
	_d text:=''::text;
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid backfeed command argument*/';
	END IF;

	_t:=j_arg->>'height';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid backfeed command argument, height is not found*/';
	END IF;	
	_htdot:=sato.helper_mmdot(_t::numeric, i_dpi);

	_t:=j_arg->>'qty';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid backfeed command argument, qty is not found*/';
	END IF;	
	_qty:=_t::numeric;

	_feed:=_htdot * _qty;
	IF _feed<i_min OR _feed>i_max THEN
		RAISE EXCEPTION '/*invalid backfeed command argument, feed length is out of range*/';
	END IF;
	
	RETURN _ESC || encode(('IK1,' || (_htdot*_qty)::text)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.intel_backfeed(smallint, integer, integer, json) FROM public;
	
CREATE OR REPLACE FUNCTION sato.system_mediasize(i_dpi smallint, i_maxlabelheight integer, i_maxlabelwidth integer, j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"mediasize",
		"arg":{"ht": mm, "wd": mm}
		}*/	
	_t text;
	_int integer;
	_d text:=''::text;
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid mediasize command argument*/';
	END IF;

	_t:=j_arg->>'ht';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid mediasize command argument, ht is not found*/';
	END IF;	
	_int:=sato.helper_mmdot(_t::numeric, i_dpi);

	IF _int > i_maxlabelheight THEN
		RAISE EXCEPTION '/*invalid mediasize command argument, ht is out range*/';
	END IF;
	_d:=_d || 'V' || _int::text;

	_t:=j_arg->>'wd';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid mediasize command argument, wd is not found*/';
	END IF;		
	_int:=sato.helper_mmdot(_t::numeric, i_dpi);

	IF _int > i_maxlabelwidth THEN
		RAISE EXCEPTION '/*invalid mediasize command argument, wd is out range*/';
	END IF;
	_d:=_d || 'H' || _int::text;
	
	RETURN _ESC || encode(('A1' || _d)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.system_mediasize(smallint, integer, integer, json) FROM public;

CREATE OR REPLACE FUNCTION sato.font_text(i_dpi smallint, j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"text",
		"arg":{"body":s, "font":{"pitch":mm,"file":sfile,"style":0-standard/1-bold/2-italic/3-bold+italic,"wd":mm,"ht":mm}}
		}*/				
	_t text;
	_d text:=''::text;
	_font json;
	_int integer;
	_ESC text:='1B';
	_MINIMUM_FONTWDDOT integer:=20;
	_MINIMUM_FONTHTDOT integer:=20;
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument*/';
	END IF;

	_font:=j_arg->'font';
	IF _font IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, font is not found*/';
	END IF;

	_t:=_font->>'pitch';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, font pitch is not found*/';
	END IF;
	_int:=sato.helper_mmdot(_t::numeric, i_dpi);
	IF _int<0 OR _int>99 THEN
		RAISE EXCEPTION '/*invalid text command argument, font pitch is out of range*/';
	END IF;
	_d:=_d || _ESC || encode( ('P' || _int::text)::bytea, 'hex');
	
	_d:=_d || _ESC || encode( ('RH0'/*UNICODE(UTF-8)*/)::bytea, 'hex');
	_t:=_font->>'file';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, font file is not found*/';
	END IF;
	_d:=_d || encode( (',' || _t)::bytea, 'hex');

	_t:=_font->>'style';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, font style is not found*/';
	END IF;
	_d:=_d || encode( (',' || (_t::integer)::text)::bytea, 'hex');

	_t:=_font->>'wd';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, font wd is not found*/';
	END IF;
	_int:=int4larger( sato.helper_mmdot(_t::numeric, i_dpi), _MINIMUM_FONTWDDOT);
	_d:=_d || encode( (',' || _int::text)::bytea, 'hex');
	
	_t:=_font->>'ht';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, font ht is not found*/';
	END IF;
	_int:=int4larger( sato.helper_mmdot(_t::numeric, i_dpi), _MINIMUM_FONTHTDOT);
	_d:=_d || encode( (',' || _int::text)::bytea, 'hex');

	_t:=j_arg->>'body';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid text command argument, body is not found*/';
	END IF;
	_d:=_d || encode( (',' || _t)::bytea, 'hex');

	RETURN _d;
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.font_text(smallint, json) FROM public;

CREATE OR REPLACE FUNCTION sato.code2d_qr(j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"qr",
		"arg":{"correctlevel":L/M/Q/H, "cellsize":n, "body":s}
		}*/				
	_t text;
	_d text:=''::text;
	_int integer;
	_MINCELLSIZE integer:=1;
	_MAXCELLSIZE integer:=99;
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid qr command argument*/';
	END IF;

	_t:=j_arg->>'correctlevel';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid qr command argument, correction level is not found*/';
	END IF;
	IF _t NOT IN ('L','M','Q','H') THEN
		RAISE EXCEPTION '/*invalid qr command argument, correction level is out of range*/';
	END IF;
	_d:=_d || ',' || _t;

	_t:=j_arg->>'cellsize';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid qr command argument, cell size is not found*/';
	END IF;
	_int:=_t::integer;
	IF _int<_MINCELLSIZE OR _int>_MAXCELLSIZE THEN
		RAISE EXCEPTION '/*invalid qr command argument, cell size is out of range*/';
	END IF;
	_d:=_d || ',' || lpad(_int::text, 2, '0') || ',0'/*data setup is manual mode*/ || ',0'/*concatenation:normal mode*/;	
	_d:=_ESC || encode(('2D30'/*model 2*/ || _d)::bytea, 'hex'::text);
	
	_t:=j_arg->>'body';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid qr command argument, body is not found*/';
	END IF;
	RETURN _d || _ESC || encode( ('DS' || '2'/*alphanumeric*/ || ',' || _t)::bytea, 'hex'::text);		
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.code2d_qr(json) FROM public;

CREATE OR REPLACE FUNCTION sato.code2d_dm(j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"dm",
		"arg":{"hsize":nn, "vsize":nn, "body":s}
		}*/				
	_t text;
	_d text:=''::text;
	_int integer;
	_MINCELLSIZE integer:=1;
	_MAXCELLSIZE integer:=99;
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid datamatrix command argument*/';
	END IF;

	_t:=j_arg->>'hsize';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid datamatrix command argument, hsize is not found*/';
	END IF;
	_int:=_t::integer;
	IF _int<_MINCELLSIZE OR _int>_MAXCELLSIZE THEN
		RAISE EXCEPTION '/*invalid datamatrix command argument, hsize size is out of range*/';
	END IF;
	_d:=_d || ',' || lpad(_int::text, 2, '0');

	_t:=j_arg->>'vsize';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid datamatrix command argument, vsize is not found*/';
	END IF;
	_int:=_t::integer;
	IF _int<_MINCELLSIZE OR _int>_MAXCELLSIZE THEN
		RAISE EXCEPTION '/*invalid datamatrix command argument, vsize size is out of range*/';
	END IF;
	_d:=_d || ',' || lpad(_int::text, 2, '0');
	
	_d:=_d || ',000,000';
	_d:=_ESC || encode(('2D50' || _d)::bytea, 'hex'::text);

	_t:=j_arg->>'body';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid datamatrix command argument, body is not found*/';
	END IF;
	RETURN _d || _ESC || encode( ('DS' || _t)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.code2d_dm(json) FROM public;

CREATE OR REPLACE FUNCTION sato.graphic_bmp(t_hex text)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"bmp",
		"arg":"bmp_in_hex_format" 
		}*/				
	/*note: successful for monochrome 1 pixel per bit bmp*/
	_t text;
	_d text:=''::text;
	_bmpsize integer;
	_ESC text:='1B';
BEGIN
	_bmpsize:=length(t_hex)/2;
	IF _bmpsize>99999 THEN
		RAISE EXCEPTION '/*invalid bmp command argument, bitmap size it out of range*/';
	END IF;
	RETURN _ESC || encode(('GM' || lpad(_bmpsize::text, 5, '0') || ',')::bytea, 'hex'::text) || t_hex;	
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.graphic_bmp(text) FROM public;

CREATE OR REPLACE FUNCTION sato.rfid_uhfwrite(j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	_ESC text:='1B';
	_MUL integer:=8;
	_MAX integer:=124;
	_len integer;
	_mod integer;	
	_pad integer;
	_t text;
	_d text := ''::text;
	/*{ "cmd":"uhfwrite",
		"arg":{"data":s, "validate":true/false}
		}*/	
BEGIN
	IF COALESCE(NULLIF(j_arg->>'validate',''), 'false')::boolean THEN
		_d:=_ESC || encode('RU,01'::bytea, 'hex'::text);
	END IF;
	_t:=j_arg->>'data';
	_len:=length(_t);
	_mod:=_len % _MUL;
	_pad:=(_len - _mod)/_MUL;
	IF _mod>0 THEN
		_pad:=_pad+1;
	END IF;
	_pad:=_pad*_MUL;
	IF _pad<_MUL  OR _pad>_MAX THEN
		RAISE EXCEPTION '/*RFID UHF data must be >=% and <=%*/', _MUL, _MAX;
	END IF;
	_t:=lpad(_t, _pad, '0');	
	_t:='e:h,epc:' || _t /*|| ',lck:00001'*/ || ';';	
	RETURN _d || _ESC || encode(('IP0' || _t)::bytea, 'hex'::text);	
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.rfid_uhfwrite(json) FROM public;

CREATE OR REPLACE FUNCTION sato.status_do(IN t_host text, IN i_port smallint,
	OUT i_printerstatus smallint, OUT t_printerstatus text,
	OUT i_bufferstatus smallint, OUT t_bufferstatus text,
	OUT i_ribbonstatus smallint, OUT t_ribbonstatus text,
	OUT i_mediastatus smallint, OUT t_mediastatus text,
	OUT i_error smallint, OUT t_error text,
	OUT i_batterystatus smallint, OUT t_batterystatus text,
	OUT i_remainprint integer
)
  RETURNS SETOF record AS
$BODY$
DECLARE
	_resp text;
	_resparr text[];
	_resparrlen integer;
	_subtext text;
	_i integer;
BEGIN
	_resp:=trim(public.pgsocketsendrcvstxetx(t_host, i_port, 30, 30, (E'\\x12' || encode('PG','hex'))::bytea )::text);	
	_resparr:=regexp_split_to_array(_resp, ',');
	_resparrlen:=cardinality(_resparr);

	i_printerstatus:=-1;	t_printerstatus:='not available';
	i_bufferstatus:=-1;		t_bufferstatus:='not available';
	i_ribbonstatus:=-1;		t_ribbonstatus:='not available';
	i_mediastatus:=-1;		t_mediastatus:='not available';
	i_error:=-1;			t_error:='not available';
	i_batterystatus:=-1;	t_batterystatus:='not available';
	i_remainprint:=-1;

	FOR _i IN 2.._resparrlen LOOP
		_subtext:=trim(_resparr[_i]);		
		IF _subtext ~ '^PS[0-9]{1,1}$' THEN
			i_printerstatus:=right(_subtext, 1)::smallint;
			t_printerstatus:=CASE WHEN i_printerstatus=0 THEN 'Standby'
				WHEN i_printerstatus=1 THEN 'Waiting for dispensing'
				WHEN i_printerstatus=2 THEN 'Analyzing'
				WHEN i_printerstatus=3 THEN 'Printing'
				WHEN i_printerstatus=4 THEN 'Offline'
				WHEN i_printerstatus=5 THEN 'Error'
				ELSE 'No explanation'
				END;
		ELSIF _subtext ~ '^RS[0-9]{1,1}' THEN
			i_bufferstatus:=right(_subtext, 1)::smallint;
			t_bufferstatus:=CASE WHEN i_bufferstatus=0 THEN 'Buffer available'
				WHEN i_bufferstatus=1 THEN 'Buffer near full'
				WHEN i_bufferstatus=2 THEN 'Buffer full'
				ELSE 'No explanation'
				END;
		ELSIF _subtext ~ '^RE[0-9]{1,1}' THEN
			i_ribbonstatus:=right(_subtext, 1)::smallint;
			t_ribbonstatus:=CASE WHEN i_ribbonstatus=0 THEN 'Ribbon present'
				WHEN i_ribbonstatus=1 THEN 'Ribbon near end'
				WHEN i_ribbonstatus=2 THEN 'No Ribbon'
				WHEN i_ribbonstatus=3 THEN 'Direct thermal model'
				ELSE 'No explanation'
				END;
		ELSIF _subtext ~ '^PE[0-9]{1,1}' THEN
			i_mediastatus:=right(_subtext, 1)::smallint;
			t_mediastatus:=CASE WHEN i_mediastatus=0 THEN 'Media present'
				WHEN i_mediastatus=2 THEN 'No media'
				ELSE 'No explanation'
				END;			
		ELSIF _subtext ~ '^EN[0-9]{2,2}' THEN
			i_error:=right(_subtext, 2)::smallint;
			t_error:=CASE WHEN i_error=0 THEN 'Online'
				WHEN i_error=1 THEN 'Offline'
				WHEN i_error=2 THEN 'Machine error'
				WHEN i_error=3 THEN 'Memory error'
				WHEN i_error=4 THEN 'Program error'
				WHEN i_error=5 THEN 'Setting information error (FLASH-ROM error)'
				WHEN i_error=6 THEN 'Setting information error (EE-PROM error)'
				WHEN i_error=7 THEN 'Download error'
				WHEN i_error=8 THEN 'Parity error'
				WHEN i_error=9 THEN 'Over run'
				WHEN i_error=10 THEN 'Framing error'
				WHEN i_error=11 THEN 'LAN timeout error'
				WHEN i_error=12 THEN 'Buffer error'
				WHEN i_error=13 THEN 'Head open'
				WHEN i_error=14 THEN 'Paper end'
				WHEN i_error=15 THEN 'Ribbon end'
				WHEN i_error=16 THEN 'Media error'
				WHEN i_error=17 THEN 'Sensor error'
				WHEN i_error=18 THEN 'Printhead error'
				WHEN i_error=19 THEN 'Cover open error'
				WHEN i_error=20 THEN 'Memory/Card type error'
				WHEN i_error=21 THEN 'Memory/Card read/write error'
				WHEN i_error=22 THEN 'Memory/Card full error'
				WHEN i_error=23 THEN 'Memory/Card no battery error'
				WHEN i_error=24 THEN 'Ribbon saver error'
				WHEN i_error=25 THEN 'Cutter error'
				WHEN i_error=26 THEN 'Cutter sensor error'
				WHEN i_error=27 THEN 'Stacker full error'
				WHEN i_error=28 THEN 'Command error'
				WHEN i_error=29 THEN 'Sensor error at Power-On'
				WHEN i_error=30 THEN 'RFID tag error'
				WHEN i_error=31 THEN 'Interface card error'
				WHEN i_error=32 THEN 'Rewinder error'
				WHEN i_error=33 THEN 'Other error'
				WHEN i_error=34 THEN 'RFID control error'
				WHEN i_error=35 THEN 'Head density error'
				WHEN i_error=36 THEN 'Kanji data error'
				WHEN i_error=37 THEN 'Calendar error'
				WHEN i_error=38 THEN 'Item No error'
				WHEN i_error=39 THEN 'BCC error'
				WHEN i_error=40 THEN 'Cutter cover open error'
				WHEN i_error=41 THEN 'Ribbon rewind non-lock error'
				WHEN i_error=42 THEN 'Communication timeout error'
				WHEN i_error=43 THEN 'Lid latch open error'
				WHEN i_error=44 THEN 'No media error at Power-On'
				WHEN i_error=45 THEN 'SD card access error'
				WHEN i_error=46 THEN 'SD card full error'
				WHEN i_error=47 THEN 'Head lift error'
				WHEN i_error=48 THEN 'Head overheat error'
				WHEN i_error=49 THEN 'SNTP time correction error'
				WHEN i_error=50 THEN 'CRC error'
				WHEN i_error=51 THEN 'Cutter motor error'
				WHEN i_error=52 THEN 'WLAN module error'
				WHEN i_error=53 THEN 'Scanner reading error'
				WHEN i_error=54 THEN 'Scanner checking error'
				WHEN i_error=55 THEN 'Scanner connection error'
				WHEN i_error=56 THEN 'Bluetooth module error'
				WHEN i_error=57 THEN 'EAP authentication error (EAP failed)'
				WHEN i_error=58 THEN 'EAP authentication error (time out)'
				WHEN i_error=59 THEN 'Battery error'
				WHEN i_error=60 THEN 'Low battery error'
				WHEN i_error=61 THEN 'Low battery error (charging)'
				WHEN i_error=62 THEN 'Battery not installed error'
				WHEN i_error=63 THEN 'Battery temperature error'
				WHEN i_error=64 THEN 'Battery deterioration error'
				WHEN i_error=65 THEN 'Motor temperature error'
				WHEN i_error=66 THEN 'Inside chassis temperature error'
				WHEN i_error=67 THEN 'Jam error'
				WHEN i_error=68 THEN 'SIPL field full error'
				WHEN i_error=69 THEN 'Power off error when charging'
				WHEN i_error=70 THEN 'WLAN module error'
				WHEN i_error=71 THEN 'Option mismatch error'
				WHEN i_error=72 THEN 'Battery deterioration error (notice)'
				WHEN i_error=73 THEN 'Battery deterioration error (warning)'
				WHEN i_error=74 THEN 'Power off error'
				WHEN i_error=75 THEN 'Non RFID warning error'
				WHEN i_error=76 THEN 'Barcode reader connection error'
				WHEN i_error=77 THEN 'Barcode reading error'
				WHEN i_error=78 THEN 'Barcode verification error'
				WHEN i_error=79 THEN 'Barcode reading error (verification start position abnormally)'
				ELSE 'No explanation'
				END;			
		ELSIF _subtext ~ '^BT[0-9]{1,1}' THEN
			i_batterystatus:=right(_subtext, 1)::smallint;
			t_batterystatus:=CASE WHEN i_batterystatus=0 THEN 'Normal'
				WHEN i_batterystatus=1 THEN 'Battery near end'
				WHEN i_batterystatus=2 THEN 'Battery error'
				ELSE 'No explanation'
				END;
		ELSIF _subtext ~ '^Q[0-9]{6,6}' THEN
			i_remainprint:=right(_subtext, 6)::integer;
		END IF;
	END LOOP;	
	RETURN NEXT;
	RETURN;
END;
$BODY$
  LANGUAGE plpgsql STABLE SECURITY DEFINER;
REVOKE ALL ON FUNCTION sato.status_do(text, smallint) FROM public;

CREATE OR REPLACE FUNCTION sato.status(IN t_server text,
	OUT i_printerstatus smallint, OUT t_printerstatus text,
	OUT i_bufferstatus smallint, OUT t_bufferstatus text,
	OUT i_ribbonstatus smallint, OUT t_ribbonstatus text,
	OUT i_mediastatus smallint, OUT t_mediastatus text,
	OUT i_error smallint, OUT t_error text,
	OUT i_batterystatus smallint, OUT t_batterystatus text,
	OUT i_remainprint integer
) RETURNS SETOF record AS
$BODY$
DECLARE
	_server record;
BEGIN
	SELECT t.* INTO _server FROM sato.server t WHERE t.id = t_server;	
	IF NOT FOUND THEN
		RAISE EXCEPTION '/*printer server % is not found*/', t_server;
	END IF;
	RETURN QUERY SELECT * FROM sato.status_do(_server.host, _server.port);
	RETURN;
END;
$BODY$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION sato.status(text) TO public;

CREATE OR REPLACE FUNCTION sato.print(IN t_server text, VARIADIC j_jobs json[], OUT b_rfidwritesuccess boolean, OUT t_err text, OUT t_epc text, OUT t_tid text)
  RETURNS SETOF record AS
$BODY$
DECLARE
	_server record;
	_ESC text:='1B';
	_START text:='A';
	_STOP text:='Z';
	_job json;
	_cmd text;
	_b text;	
	_status record;
	_statusloop smallint;
	_MAXSTATUSLOOP smallint:=10;
	_needribbon boolean:=false;
	_needmedia boolean:=false;	
	_needresponse boolean:=false;
-------------------------	
	_resp text;
	_resparr text[];
	_resparrlen integer;
	_i integer;
	_errcode text;
	_subtext text;	
BEGIN
	SELECT t.* INTO _server FROM sato.server t WHERE t.id = t_server FOR UPDATE;--prevent hardware access conflict	
	IF NOT FOUND THEN
		RAISE EXCEPTION '/*printer server % is not found*/', t_server;
	END IF;
	_b:=_ESC || encode(_START::bytea, 'hex');		
	FOREACH _job IN ARRAY j_jobs LOOP
		_cmd:=_job->>'cmd';
		IF _cmd = 'y' THEN
			_b:=_b || sato.position_vert(_server.dpi, _server.maxvert, (_job->>'arg')::numeric);
		ELSIF _cmd = 'x' THEN
			_b:=_b || sato.position_horz(_server.dpi, _server.maxhorz, (_job->>'arg')::numeric);
		ELSIF _cmd = 'origin' THEN
			_b:=_b || sato.position_origin(_server.dpi, _server.maxvert, _server.maxhorz, _job->'arg');
		ELSIF _cmd = 'mediasize' THEN		
			_b:=_b || sato.system_mediasize(_server.dpi, _server.maxlabelheight, _server.maxlabelwidth, _job->'arg');
		ELSIF _cmd = 'text' THEN
			_needribbon:=true;
			_needmedia:=true;
			_b:=_b || sato.font_text(_server.dpi, _job->'arg');
		ELSIF _cmd = 'qr' THEN
			_needribbon:=true;
			_needmedia:=true;		
			_b:=_b || sato.code2d_qr(_job->'arg');
		ELSIF _cmd = 'dm' THEN
			_needribbon:=true;
			_needmedia:=true;		
			_b:=_b || sato.code2d_dm(_job->'arg');
		ELSIF _cmd = 'bmp' THEN
			_needribbon:=true;
			_needmedia:=true;		
			_b:=_b || sato.graphic_bmp(_job->>'arg');
		ELSIF _cmd = 'qty' THEN
			_b:=_b || sato.control_qty((_job->>'arg')::integer);
		ELSIF _cmd = 'feed' THEN
			_b:=_b || sato.intel_feed(_server.dpi, _server.minfeed, _server.maxfeed, _job->'arg');
		ELSIF _cmd = 'backfeed' THEN
			_b:=_b || sato.intel_backfeed(_server.dpi, _server.minbackfeed, _server.maxbackfeed, _job->'arg');			
		ELSIF _cmd = 'uhfwrite' THEN
			_needmedia:=true;
			_needresponse:= COALESCE(NULLIF(((_job->'arg')->>'validate'),''), 'false')::boolean;
			_b:=_b || sato.rfid_uhfwrite(_job->'arg');			
		ELSE
			RAISE EXCEPTION '/*invalid command %*/', _cmd;
		END IF;
	END LOOP;			
	_b:= E'\\x' || _b || _ESC || encode(_STOP::bytea, 'hex');

	_statusloop:=0;
	LOOP
		_statusloop:=_statusloop+1;
		SELECT * INTO _status FROM sato.status_do(_server.host, _server.port);
		IF _status.i_error != 0 THEN
			RAISE EXCEPTION '/*printer error: %*/', _status.t_error;
		END IF;
		IF _status.i_printerstatus !=0 THEN
			IF _status.i_printerstatus IN (4,5) OR _statusloop > _MAXSTATUSLOOP THEN
				RAISE EXCEPTION '/*printer error: %*/', _status.t_printerstatus;
			END IF;
			PERFORM pg_sleep(0.5);
			CONTINUE;				
		END IF;
		IF _status.i_bufferstatus !=0 THEN
			IF _statusloop > _MAXSTATUSLOOP THEN
				RAISE EXCEPTION '/*printer error: %*/', _status.t_bufferstatus;
			END IF;
			PERFORM pg_sleep(0.5);
			CONTINUE;
		END IF;
		IF _needribbon AND _status.i_ribbonstatus=2 THEN
			RAISE EXCEPTION '/*printer error: %*/', _status.t_ribbonstatus;
		END IF;
		IF _needmedia AND _status.i_mediastatus !=0 THEN
			RAISE EXCEPTION '/*printer error: %*/', _status.t_mediastatus;
		END IF;
		IF _needmedia AND _status.i_batterystatus = 2 THEN
			RAISE EXCEPTION '/*printer error: %*/', _status.t_batterystatus;
		END IF;		
		EXIT;
	END LOOP;
	
	PERFORM public.pgsocketsend(_server.host, _server.port, 30/*timeoutseconds*/, _b::bytea);	
	IF _needresponse THEN
		_statusloop:=0;
		LOOP
			PERFORM pg_sleep(0.5);
			_statusloop:=_statusloop+1;
			SELECT * INTO _status FROM sato.status_do(_server.host, _server.port);
			IF _status.i_printerstatus != 0 THEN
				IF _statusloop > (2*_MAXSTATUSLOOP) THEN
					RAISE EXCEPTION '/*printer error: %*/', _status.t_printerstatus;
				END IF;			
				CONTINUE;
			END IF;
			EXIT;
		END LOOP;
		_resp:=public.pgsocketsendrcvstxetx(_server.host, _server.port, 30, 30, (E'\\x12' || encode('PK','hex'))::bytea )::text;
		_resp:=regexp_replace(trim(_resp), '\\015\\012$', '');		
		_resparr:=regexp_split_to_array(_resp, ',');
		b_rfidwritesuccess:=_resparr[2]='1';
		_errcode:=_resparr[3];
		t_err:='Unexplained error';
		IF _errcode='N' THEN
			t_err:='No error';
		ELSIF _errcode='U' THEN
			t_err:='UID read error';
		ELSIF _errcode='A' THEN
			t_err:='All errors';
		END IF;
		t_epc:=NULL::text;
		t_tid:=NULL::text;
		_resparrlen:=cardinality(_resparr);
		FOR _i IN 4..int4smaller(_resparrlen,5) LOOP
			_subtext:=substr(_resparr[_i],1,3);
			IF _subtext='EP:' THEN
				t_epc:=substr(_resparr[_i], 4);
			ELSIF _subtext='ID:' THEN
				t_tid:=substr(_resparr[_i], 4);
			END IF;
		END LOOP;
		RETURN NEXT;		
	END IF;
	RETURN;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION sato.print(text, json[]) TO public;