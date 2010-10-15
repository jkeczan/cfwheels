<cffunction name="$generatedKey" returntype="string" access="public" output="false">
	<cfreturn "rowid">
</cffunction>

<cffunction name="$randomOrder" returntype="string" access="public" output="false">
	<cfreturn "dbms_random.value()">
</cffunction>

<cffunction name="$getType" returntype="string" access="public" output="false">
	<cfargument name="type" type="string" required="true">
	<cfargument name="scale" type="string" required="true">
	<cfscript>
		var loc = {};
		switch(arguments.type)
		{
			case "blob": case "bfile": {loc.returnValue = "cf_sql_blob"; break;}
			case "char": case "nchar": {loc.returnValue = "cf_sql_char"; break;}
			case "clob": case "nclob": {loc.returnValue = "cf_sql_clob"; break;}
			case "date": case "timestamp": {loc.returnValue = "cf_sql_timestamp"; break;}
			case "binary_double": {loc.returnValue = "cf_sql_double"; break;}
			case "number": case "float": case "binary_float":
			{
				// integer datatypes are represented by number(38,0)
				if (val(arguments.scale) == 0)
				{
					loc.returnValue = "cf_sql_integer";
				}
				else
				{
					loc.returnValue = "cf_sql_float";
				}
				break;
			}
			case "long": {loc.returnValue = "cf_sql_longvarchar"; break;}
			case "raw": {loc.returnValue = "cf_sql_varbinary"; break;}
			case "varchar2": case "nvarchar2": {loc.returnValue = "cf_sql_varchar"; break;}
		}
	</cfscript>
	<cfreturn loc.returnValue>
</cffunction>

<cffunction name="$query" returntype="struct" access="public" output="false">
	<cfargument name="sql" type="array" required="true">
	<cfargument name="limit" type="numeric" required="false" default=0>
	<cfargument name="offset" type="numeric" required="false" default=0>
	<cfargument name="parameterize" type="boolean" required="true">
	<cfargument name="$primaryKey" type="string" required="false" default="">
	<cfscript>
		var loc = {};

		arguments.sql = $removeColumnAliasesInOrderClause(arguments.sql);
		if (arguments.limit > 0)
		{
			loc.beforeWhere = "SELECT * FROM (SELECT a.*, rownum rnum FROM (";
			loc.afterWhere = ") a WHERE rownum <=" & arguments.limit+arguments.offset & ")" & " WHERE rnum >" & arguments.offset;
			ArrayPrepend(arguments.sql, loc.beforeWhere);
			ArrayAppend(arguments.sql, loc.afterWhere);
		}

		// oracle doesn't support limit and offset in sql
		StructDelete(arguments, "limit", false);
		StructDelete(arguments, "offset", false);
		loc.returnValue = $performQuery(argumentCollection=arguments);
		loc.returnValue = $handleTimestampObject(loc.returnValue);
	</cfscript>
	<cfreturn loc.returnValue>
</cffunction>

<cffunction name="$identitySelect" returntype="any" access="public" output="false">
	<cfargument name="queryAttributes" type="struct" required="true">
	<cfargument name="result" type="struct" required="true">
	<cfargument name="primaryKey" type="string" required="true">
	<cfset var loc = {}>
	<cfset var query = {}>
	<cfset loc.sql = Trim(arguments.result.sql)>
	<cfif Left(loc.sql, 11) IS "INSERT INTO">
		<cfset arguments.table = SpanExcluding(Right(loc.sql, Len(loc.sql)-12), " ")>
		<cfset arguments.primaryKey = ListFirst(arguments.primaryKey)>
		<cfif NOT StructKeyExists(arguments.result, $generatedKey())>
			<cfset loc.startPar = Find("(", loc.sql) + 1>
			<cfset loc.endPar = Find(")", loc.sql)>
			<cfset loc.columnList = ReplaceList(Mid(loc.sql, loc.startPar, (loc.endPar-loc.startPar)), "#Chr(10)#,#Chr(13)#, ", ",,")>
			<cfif NOT ListFindNoCase(loc.columnList, arguments.primaryKey)>
				<cfreturn $identityRetrieve(argumentCollection=arguments)>
			</cfif>
		<cfelse>
			<cfreturn $identityRetrieve(argumentCollection=arguments)>
		</cfif>
	</cfif>
</cffunction>

<cffunction name="$identityRetrieve" access="public" returntype="any" output="false">
	<cfargument name="queryAttributes" type="struct" required="true">
	<cfargument name="result" type="struct" required="true">
	<cfargument name="primaryKey" type="string" required="true">
	<cfargument name="table" type="string" required="true">
	<cfset var loc = {}>
	<cfset var query = {}>
	<cfquery attributeCollection="#arguments.queryAttributes#">SELECT #arguments.primaryKey# AS lastId FROM #arguments.table# WHERE ROWID = '#arguments.result[$generatedKey()]#'</cfquery>
	<cfset loc.returnValue[$generatedKey()] = Trim(query.name.lastId)>
	<cfreturn loc.returnValue>
</cffunction>

<cffunction name="$$dbinfo">
	<cfscript>
	var loc = {};
	loc.args = duplicate(variables.instance.connection);
	loc.args.name = "loc.returnValue";
	</cfscript>

	<cfquery attributeCollection="#loc.args#">
	SELECT  TC.COLUMN_NAME,
			TC.DATA_TYPE AS TYPE_NAME,
			TC.NULLABLE AS IS_NULLABLE,
			CASE WHEN PKC.COLUMN_NAME IS NULL THEN 0 ELSE 1 END AS IS_PRIMARYKEY,
			0 AS IS_FOREIGNKEY,
			'' AS REFERENCED_PRIMARYKEY,
			'' AS REFERENCED_PRIMARYKEY_TABLE,
			NVL(TC.DATA_PRECISION, TC.DATA_LENGTH) AS COLUMN_SIZE,
			TC.DATA_SCALE AS DECIMAL_DIGITS,
			TC.DATA_DEFAULT AS COLUMN_DEFAULT_VALUE,
			TC.DATA_LENGTH AS CHAR_OCTET_LENGTH,
			TC.COLUMN_ID AS ORDINAL_POSITION,
			'' AS REMARKS
	FROM ALL_TAB_COLUMNS TC
	LEFT JOIN ALL_CONSTRAINTS PK ON (PK.CONSTRAINT_TYPE = 'P' AND PK.TABLE_NAME = TC.TABLE_NAME AND TC.OWNER = PK.OWNER)
	LEFT JOIN ALL_CONS_COLUMNS PKC ON (PK.CONSTRAINT_NAME = PKC.CONSTRAINT_NAME AND TC.COLUMN_NAME = PKC.COLUMN_NAME AND TC.OWNER = PKC.OWNER)
	WHERE TC.TABLE_NAME = '#UCase(arguments.table)#'
	ORDER BY TC.COLUMN_ID
	</cfquery>

	<cfreturn loc.returnValue>
</cffunction>

<cffunction name="$handleTimestampObject"
	hint="Oracle will return timestamp as an object. you need to call timestampValue() to get the string representation">
	<cfargument name="results" type="struct" required="true">
	<cfscript>
	var loc = {};
	// only do this for Adobe Coldfusion, if a query exists and if the JDBC_MAJOR_VERSION is greater than 9 (8 doesn't have this problem)
	if (application.wheels.serverName eq "Adobe ColdFusion" && variables.instance.info.driver_name eq "Oracle JDBC driver" && StructKeyExists(arguments.results, "query") && variables.instance.info.JDBC_MAJOR_VERSION gt 8)
	{
		// look for all timestamp columns
		loc.query = arguments.results.query;
		loc.rows = loc.query.RecordCount;
		if (loc.rows gt 0)
		{
			loc.metadata = GetMetaData(loc.query);
			loc.columns = [];
			loc.iEnd = ArrayLen(loc.metadata);
			for (loc.i = 1; loc.i lte loc.iEnd; loc.i++)
			{
				loc.column = loc.metadata[loc.i];
				if (loc.column.typename eq "timestamp")
				{
					ArrayAppend(loc.columns, loc.column.name);
				}
			}

			// if we have any timestamp columns
			if (!ArrayIsEmpty(loc.columns))
			{
				loc.iEnd = ArrayLen(loc.columns);
				for (loc.i = 1; loc.i lte loc.iEnd; loc.i++)
				{
					loc.column = loc.columns[loc.i];
					for (loc.row = 1; loc.row lte loc.rows; loc.row++)
					{
						if (IsObject(loc.query[loc.column][loc.row]))
						{
							loc.query[loc.column][loc.row] = loc.query[loc.column][loc.row].timestampValue();
						}
					}
				}
			}
			arguments.results.query = loc.query;
		}
	}
	return arguments.results;
	</cfscript>
</cffunction>