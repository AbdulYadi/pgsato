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

CREATE OR REPLACE FUNCTION sato.system_mode(t_mode text)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"mode",
		"arg": "0/1/2/3/4/5/6/7/8/B"
		}*/	
	_ESC text:='1B';
BEGIN
	IF COALESCE(t_mode,'') NOT IN  ('0','1','2','3','4','5','6','7','8','B') THEN
		RAISE EXCEPTION '/*mode command argument is out of range*/';
	END IF;
	RETURN _ESC || encode(('PM' || t_mode)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.system_mode(text) FROM public;

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

CREATE OR REPLACE FUNCTION sato.modif_ratio(j_arg json)
  RETURNS text AS
$BODY$
DECLARE
	/*{ "cmd":"ratio",
		"arg":{"v": nn, "h": nn}
		}*/	
	_t text;
	_int integer;
	_d text:=''::text;
	_MINRATIO integer:=1;
	_MAXRATIO integer:=36;
	_ESC text:='1B';
BEGIN
	IF j_arg IS NULL THEN
		RAISE EXCEPTION '/*invalid ratio command argument*/';
	END IF;

	_t:=j_arg->>'v';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid ratio command argument, v is not found*/';
	END IF;	
	_int:=_t::integer;
	IF _int<_MINRATIO OR _int>_MAXRATIO THEN
		RAISE EXCEPTION '/*invalid ratio command argument, v is out of range*/';
	END IF;
	_d:=_d || lpad(_int::text, 2, '0');

	_t:=j_arg->>'h';
	IF _t IS NULL THEN
		RAISE EXCEPTION '/*invalid ratio command argument, h is not found*/';
	END IF;	
	_int:=_t::integer;
	IF _int<_MINRATIO OR _int>_MAXRATIO THEN
		RAISE EXCEPTION '/*invalid ratio command argument, h is out of range*/';
	END IF;
	_d:=_d || lpad(_int::text, 2, '0');

	RETURN _ESC || encode(('L' || _d)::bytea, 'hex'::text);
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.modif_ratio(json) FROM public;

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
		RAISE EXCEPTION '/*RFID UHF data must be >=4 and <=124*/';
	END IF;
	_t:=lpad(_t, _pad, '0');	
	_t:='e:h,epc:' || _t /*|| ',lck:00001'*/ || ';';	
	RETURN _d || _ESC || encode(('IP0' || _t)::bytea, 'hex'::text);	
END;
$BODY$
  LANGUAGE plpgsql IMMUTABLE;
REVOKE ALL ON FUNCTION sato.rfid_uhfwrite(json) FROM public;

DROP FUNCTION IF EXISTS sato.print(text, json[]);
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
	_needresponse boolean:=false;
-------------------------	
	_resp text;
	_resparr text[];
	_resparrlen integer;
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
		ELSIF _cmd = 'mode' THEN
			_b:=_b || sato.system_mode(_job->>'arg');			
		ELSIF _cmd = 'text' THEN
			_b:=_b || sato.font_text(_server.dpi, _job->'arg');
		ELSIF _cmd = 'qr' THEN
			_b:=_b || sato.code2d_qr(_job->'arg');
		ELSIF _cmd = 'dm' THEN
			_b:=_b || sato.code2d_dm(_job->'arg');
		ELSIF _cmd = 'bmp' THEN
			_b:=_b || sato.graphic_bmp(_job->>'arg');
		ELSIF _cmd = 'qty' THEN
			_b:=_b || sato.control_qty((_job->>'arg')::integer);
		ELSIF _cmd = 'ratio' THEN
			_b:=_b || sato.modif_ratio(_job->'arg');			
		ELSIF _cmd = 'feed' THEN
			_b:=_b || sato.intel_feed(_server.dpi, _server.minfeed, _server.maxfeed, _job->'arg');
		ELSIF _cmd = 'backfeed' THEN
			_b:=_b || sato.intel_backfeed(_server.dpi, _server.minbackfeed, _server.maxbackfeed, _job->'arg');			
		ELSIF _cmd = 'uhfwrite' THEN
			_needresponse:= COALESCE(NULLIF(((_job->'arg')->>'validate'),''), 'false')::boolean;
			_b:=_b || sato.rfid_uhfwrite(_job->'arg');			
		ELSE
			RAISE EXCEPTION '/*invalid command %*/', _cmd;
		END IF;
	END LOOP;			
	_b:= E'\\x' || _b || _ESC || encode(_STOP::bytea, 'hex');
	PERFORM public.pgsocketsend(_server.host, _server.port, 30/*timeoutseconds*/, _b::bytea);	
	IF _needresponse THEN
		PERFORM pg_sleep(2);
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
		IF _resparrlen>3 THEN
			_subtext:=substr(_resparr[4],1,3);
			IF _subtext='EP:' THEN
				t_epc:=substr(_resparr[4], 4);
			ELSIF _subtext='ID:' THEN
				t_tid:=substr(_resparr[4], 4);
			END IF;
		END IF;
		IF _resparrlen>4 THEN
			_subtext:=substr(_resparr[5],1,3);
			IF _subtext='EP:' THEN
				t_epc:=substr(_resparr[5], 4);
			ELSIF _subtext='ID:' THEN
				t_tid:=substr(_resparr[5], 4);
			END IF;		
		END IF;		
		RETURN NEXT;		
	END IF;
	RETURN;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION sato.print(text, json[]) TO public;