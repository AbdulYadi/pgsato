# pgsato
This project contains PostgreSQL SQL file which depends on <b>pgsocket</b>.<br />

The SQL file contains command:<br />
1. Create <b>sato</b> schema if not exists.<br />
2. Create <b>sato.server</b> table if not exists.<br />
3. Create user defined functions if not exists.<br />

Run SQL file with following command (replace text in <...> with your specific setting):<br />
$ &lt;path-to-psql&gt;psql -U &lt;db_user&gt; -h &lt;db_host&gt; -p &lt;db_port&gt; -f sato.sql -d &lt;db_name&gt;
