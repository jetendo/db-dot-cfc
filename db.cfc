<!--- 
db.cfc
Version: 0.1.001

Project Home Page: https://www.jetendo.com/manual/view/current/2.1/db-dot-cfc.html
Github Home Page: https://github.com/jetendo/db-dot-cfc

Licensed under the MIT license
http://www.opensource.org/licenses/mit-license.php
Copyright (c) 2013 Far Beyond Code LLC.
 --->
<cfcomponent output="no" name="db.cfc" hint="Enhances cfquery by analyzing SQL to enforce security & framework conventions.">
	<cfoutput>
    <cffunction name="init" access="public" output="no">
    	<cfargument name="ts" type="struct" required="no">
		<cfscript>
		variables.config={
			insertIdSQL:"select last_insert_id() id", // the select statement required to retrieve the ID just inserted by an insert query.  Automatically executed when using db.insert()
			identifierQuoteCharacter:'`', // Modify the character that should surround database, table or field names.
			dbtype:'datasource', // query, hsql or datasource are valid values.
			datasource:false, // Optional change the datasource.  This option is required if the query doesn't use dbQuery.table().
			enableTablePrefixing:true, // This allows a table that is usually named "user", to be prefixed so that it is automatically verified/modified to be "prefix_user" when using this component
			autoReset:true, // Set to false to allow the current db object to retain it's configuration after running db.execute().  Only the parameters will be cleared.
			lazy:false, // Railo's lazy="true" option returns a simple Java resultset instead of the ColdFusion compatible query result.  This reduces memory usage when some of the columns are unused.
			cacheForSeconds:0, // optionally set to a number of seconds to enable query caching
			tablePrefix:"", // Set a table prefix string to be prepend to all table names.
			sql:"", // specify the full sql statement
			verifyQueriesEnabled:false, // Enabling sql verification takes more cpu time, so it should only run when testing in development.
			parseSQLFunctionStruct:{}, // Each struct key value should be a function that accepts and returns parsedSQLStruct. Prototype: struct customFunction(required struct parsedSQLStruct, required string defaultDatabaseName);
			cacheStructKey:'variables.cacheStruct', // Set to an application or server scope struct to store this data in shared memory. Use structnew('soft') on railo to have automatic garbage collection when the JVM is low on memory.
			cacheEnabled: true // Set to false to disable the query cache
		};
		if(structkeyexists(arguments, 'ts')){
			structappend(variables.config, arguments.ts, true);
			if(structkeyexists(arguments.ts, 'parseSQLFunctionStruct')){
				variables.config.parseSQLFunctionStruct=arguments.ts.parseSQLFunctionStruct;
			}
		}
		variables.tableSQLString=":ztablesql:";
		variables.trustSQLString=":ztrustedsql:";
		if(not structkeyexists(variables, 'cacheStruct')){
			variables.cacheStruct={};
		}
		variables.lastSQL="";
		variables.cachedQueryObject=createobject("dbQuery");
		return this;
        </cfscript>
    </cffunction>
    
    <cffunction name="getConfig" access="public" output="no" returntype="struct">
    	<cfscript>
		return duplicate(variables.config);
		</cfscript>
    </cffunction>
    
    <cffunction name="processSQL" access="private" output="no" returntype="string">
    	<cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
		var processedSQL=0;
		if(arguments.configStruct.verifyQueriesEnabled){
			if(compare(arguments.configStruct.sql, variables.lastSQL) NEQ 0){
				variables.lastSQL=arguments.configStruct.sql;
				variables.verifySQLParamsAreSecure(arguments.configStruct);
				processedSQL=replacenocase(arguments.configStruct.sql,variables.trustSQLString,"","all");
				processedSQL=trim(variables.parseSQL(arguments.configStruct, processedSQL, arguments.configStruct.datasource));
			}else{
				processedSQL=trim(replacenocase(replacenocase(arguments.configStruct.sql,variables.trustSQLString,"","all"), variables.tableSQLString, "","all"));
			}
		}else{
			processedSQL=trim(arguments.configStruct.sql);
		}
		return processedSQL;
		</cfscript>
    </cffunction>
    
    
    <cffunction name="checkQueryCache" access="private" output="no" returntype="struct">
    	<cfargument name="cacheStruct" type="struct" required="yes">
    	<cfargument name="configStruct" type="struct" required="yes">
    	<cfargument name="sql" type="string" required="yes">
    	<cfargument name="nowDate" type="date" required="yes">
        <cfscript>
		var arrOption=[];
		var paramIndex=0;
		var paramKey=0;
		var hashCode=0;
		var currentParamStruct=arguments.configStruct.arrParam;
		var paramCount=arraylen(currentParamStruct);
		arrayappend(arrOption, "dbtype="&arguments.configStruct.dbtype&chr(10)&"datasource="&arguments.configStruct.datasource&chr(10)&"lazy="&arguments.configStruct.lazy&chr(10)&"cacheForSeconds="&arguments.configStruct.cacheForSeconds&chr(10)&"tablePrefix="&arguments.configStruct.tablePrefix&chr(10)&"sql="&arguments.sql&chr(10));
		for(paramIndex=1;paramIndex LTE paramCount;paramIndex++){
			for(paramKey in currentParamStruct[paramIndex]){
				arrayAppend(arrOption, paramKey&"="&currentParamStruct[paramIndex][paramKey]&chr(10));
			}
		}
		hashCode=hash(arraytolist(arrOption,""),"sha-256");
		if(structkeyexists(cacheStruct, hashCode)){
			if(datediff("s", cacheStruct[hashCode].date, arguments.nowDate) LT arguments.configStruct.cacheForSeconds){
				arguments.configStruct.dbQuery.reset();
				return { success:true, hashCode:hashCode, result:cacheStruct[hashCode].result };
			}else{
				structdelete(cacheStruct, hashCode);
			}
		}
		return {success:false, hashCode:hashCode};
		</cfscript>
    </cffunction>
    
    
    <cffunction name="runQuery" access="private" returntype="any" output="no">
    	<cfargument name="configStruct" type="struct" required="yes">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
    	<cfargument name="sql" type="string" required="yes">
    	<cfscript>
		var running=true;
        var queryStruct={
			lazy=arguments.configStruct.lazy,
			datasource=arguments.configStruct.datasource	
		};
        var cfquery=0;
        var db=structnew();
		var startIndex=1;
		var tempSQL=0;
		var paramCount=arraylen(arguments.configStruct.arrParam);
		var questionMarkPosition=0;
		var paramIndex=1;
		var paramDump=0;
		if(arguments.configStruct.dbtype NEQ "" and arguments.configStruct.dbtype NEQ "datasource"){
			queryStruct.dbtype=arguments.configStruct.dbtype;	
			structdelete(queryStruct, 'datasource');
		}else if(isBoolean(queryStruct.datasource)){
			throw("dbQuery.init({datasource:datasource}) must be set before running dbQuery.execute() by either using dbQuery.table() or db.datasource=""myDatasource"";", "database");
		}
		queryStruct.name="db."&arguments.name;
		</cfscript>
		<cfif paramCount>
            <cfquery attributeCollection="#queryStruct#"><cfloop condition="#running#"><cfscript>
                questionMarkPosition=find("?", arguments.sql, startIndex);
                </cfscript><cfif questionMarkPosition EQ 0><cfscript>
				if(paramCount and paramIndex-1 GT paramCount){
					throw("dbQuery.execute() failed: There were more question marks then parameters in the current sql statement.  You must use dbQuery.param() to specify parameters.  A literal question mark is not allowed.<br /><br />SQL Statement:<br />"&arguments.sql, "database");
				}
				running=false;
				</cfscript><cfelse><cfset tempSQL=mid(arguments.sql, startIndex, questionMarkPosition-startIndex)>#preserveSingleQuotes(tempSQL)#<cfqueryparam attributeCollection="#arguments.configStruct.arrParam[paramIndex]#"><cfscript>
                startIndex=questionMarkPosition+1;
                paramIndex++;
                </cfscript></cfif></cfloop><cfscript>
				if(paramCount GT paramIndex-1){ 
					variables.throwErrorForTooManyParameters(arguments.configStruct);
				}
                tempSQL=mid(arguments.sql, startIndex, len(arguments.sql)-(startIndex-1));
                </cfscript>#preserveSingleQuotes(tempSQL)#</cfquery>
        <cfelse>
            <cfquery attributeCollection="#queryStruct#">#preserveSingleQuotes(arguments.sql)#</cfquery>
        </cfif>
        <cfscript>
		if(structkeyexists(db, arguments.name)){
			return db[arguments.name];
		}else{
			return true;
		}
		</cfscript>
    </cffunction>
    
    <cffunction name="throwErrorForTooManyParameters" access="private" output="no">
    	<cfargument name="configStruct" type="struct" required="yes">
    	<cfscript>
		var errorMessage="dbQuery.execute() failed: There were more parameters then question marks in the current sql statement.  You must run dbQuery.execute() before building any additional sql statements with the same db object.  If you need to build multiple queries before executing the query, you must create a new dbQuery object using db.newQuery();<br /><br />";
		savecontent variable="paramDump"{
			writedump(arguments.configStruct.arrParam);	
		}
		throw(errorMessage&"<br />Current SQL Statement:<br />"&arguments.configStruct.sql&"<br />Parameters:<br />"&paramDump, "database");
		</cfscript>
	</cffunction>
    
    <cffunction name="newQuery" access="public">
    	<cfargument name="config" type="struct" required="no">
        <cfscript>
		var queryCopy=duplicate(variables.cachedQueryObject);
		arguments.config.dbQuery=queryCopy;
		if(structkeyexists(arguments, 'config')){
			queryCopy.init(this, arguments.config);
		}else{
			queryCopy.init(this);
		}
		return queryCopy;
		</cfscript>
	</cffunction>
    
    <cffunction name="insertAndReturnID" access="package" returntype="any" output="no" hint="Executes the insert statement and returns the inserted ID if insert was successful.">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
    	<cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
		var db=0;
		var result=variables.execute(arguments.name, arguments.configStruct);
        var queryStruct={
			lazy=arguments.configStruct.lazy,
			datasource=arguments.configStruct.datasource,
			name:"db."&arguments.name&"_id"
		};
		</cfscript>
        <cfif result.success>
            <cfquery attributeCollection="#queryStruct#">
            #preserveSingleQuotes(arguments.configStruct.insertIDSQL)#
            </cfquery>
            <cfreturn {success:true, result:db[arguments.name&"_id"]}>
		<cfelse>
        	<cfreturn result>
		</cfif>
    </cffunction>
    
    <cffunction name="execute" access="package" returntype="struct" output="yes">
    	<cfargument name="name" type="variablename" required="yes" hint="A variable name for the query result.  Helps to identify query when debugging.">
    	<cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
		var cacheStruct=structget(arguments.configStruct.cacheStructKey);
		if(not structkeyexists(arguments.configStruct, 'sql') or not len(arguments.configStruct.sql)){
			throw("The sql statement must be set before executing the query;", "database");
		}
		
		local.processedSQL=variables.processSQL(arguments.configStruct);
		if(arguments.configStruct.cacheEnabled and arguments.configStruct.cacheForSeconds and left(local.processedSQL, 7) EQ "SELECT "){
			local.tempCacheEnabled=true;
		}else{
			local.tempCacheEnabled=false;
		}
		if(local.tempCacheEnabled){
			local.nowDate=now();
			local.cacheResult=variables.checkQueryCache(cacheStruct, arguments.configStruct, local.processedSQL, local.nowDate);
			if(local.cacheResult.success){
				return {success:true, result:local.cacheResult.result};
			}
		}
		try{
			local.result=variables.runQuery(arguments.configStruct, arguments.name, local.processedSQL);
		}catch(database errorStruct){
			arguments.configStruct.dbQuery.reset();
			if(left(trim(local.processedSQL), 7) EQ "INSERT "){
				return {success:false};
			}else{
				rethrow;
			}
		}
		arguments.configStruct.dbQuery.reset();
		if(isQuery(local.result)){
			if(local.tempCacheEnabled){
				cacheStruct[local.cacheResult.hashCode]={date:local.nowDate, result:local.result};
			}
			return {success:true, result:local.result};
		}else{
            return {success:true, result: true};
		}
        </cfscript>
    </cffunction>
    
    
    <cffunction name="getCleanSQL" access="private" output="no" returntype="string">
        <cfargument name="sql" type="string" required="yes">
        <cfscript>
		return replace(replace(arguments.sql, variables.trustSQLString, "", "all"), variables.tableSQLString, "", "all");
		</cfscript>
    </cffunction>
    
    <cffunction name="verifySQLParamsAreSecure" access="private" output="no" returntype="any">
        <cfargument name="configStruct" type="struct" required="yes">
        <cfscript>
        var sql=arguments.configStruct.sql;
		// strip trusted sql
        sql=rereplace(sql, variables.trustSQLString&".*?"&variables.trustSQLString, chr(9), "all");
		
		// detect string literals
        if(find("'", sql) NEQ 0 or find('"', sql) NEQ 0){
            throw("The SQL statement can't contain single or double quoted string literals when using the db component.  You must use dbQuery.param() to specify all values including constants.<br /><br />SQL Statement:<br />"&variables.getCleanSQL(arguments.configStruct.sql), "database");	
        }
		// strip c style comments
        sql=replace(sql, chr(10), " ", "all");
        sql=replace(sql, chr(13), " ", "all");
        sql=replace(sql, chr(9), " ", "all");
        sql=replace(sql, "/*", chr(10), "all");
        sql=replace(sql, "*/", chr(13), "all");
        sql=replace(sql, "*", chr(9), "all");
        sql=rereplace(sql, chr(10)&"[^\*]*?"&chr(13), chr(9), "all");
		
		// strip table/db/field names
		if(arguments.configStruct.identifierQuoteCharacter NEQ "" and arguments.configStruct.identifierQuoteCharacter NEQ "'"){
        	sql=rereplace(sql, arguments.configStruct.identifierQuoteCharacter&"[^"&arguments.configStruct.identifierQuoteCharacter&"]*"&arguments.configStruct.identifierQuoteCharacter, chr(9), "all");
		}
		
		// strip words not beginning with a number
        sql=rereplace(sql, "[a-zA-Z_][a-zA-Z\._0-9]*", chr(9), "all");
        
		// detect any remaining numbers
		if(refind("[0-9]", sql) NEQ 0){
			throw("The SQL statement can't contain literal numbers when using the db component.  You must use dbQuery.param() to specify all values including constants.<br /><br />SQL Statement:<br />"&variables.getCleanSQL(arguments.configStruct.sql), "database"); 	
        }
        return sql;
        </cfscript> 
    </cffunction>
    
    <cffunction name="parseSQL" access="private" output="no" returntype="any">
        <cfargument name="configStruct" type="struct" required="yes">
        <cfargument name="sqlString" type="string" required="yes">
        <cfargument name="defaultDatabaseName" type="string" required="yes">
        <cfscript>
		var tableStruct={};
        var local={};
		var i=0;
		var parseStruct={};
        var tempSQL=arguments.sqlString;
        parseStruct.arrError=arraynew(1);
        parseStruct.arrTable=arraynew(1);
        tempSQL=replace(replace(replace(replace(replace(tempSQL,chr(10)," ","all"),chr(9)," ","all"),chr(13)," ","all"),")"," ) ","all"),"("," ( ","all");
        tempSQL=" "&rereplace(replace(replace(replace(lcase(tempSQL),"\\"," ","all"),"\'"," ","all"),'\"'," ","all"), "/\*.*?\*/"," ", "all")&" ";
        tempSQL=rereplace(tempSQL,"'[^']*?'","''","all");
        tempSQL=rereplace(tempSQL,'"[^"]*?"',"''","all");
        
        parseStruct.wherePos=findnocase(" where ",tempSQL);
        parseStruct.setPos=findnocase(" set ",tempSQL);
        parseStruct.valuesPos=refindnocase("\)\s*values",tempSQL);
        parseStruct.fromPos=findnocase(" from ",tempSQL);
        parseStruct.selectPos=findnocase(" select ",tempSQL);
        parseStruct.insertPos=findnocase(" insert ",tempSQL);
        parseStruct.replacePos=findnocase(" replace ",tempSQL);
        parseStruct.intoPos=findnocase(" into ",tempSQL);
        parseStruct.limitPos=findnocase(" limit ",tempSQL);
        parseStruct.groupByPos=findnocase(" group by ",tempSQL);
        parseStruct.orderByPos=findnocase(" order by ",tempSQL);
        parseStruct.havingPos=findnocase(" having ",tempSQL);
        parseStruct.firstLeftJoinPos=findnocase(" left join ",tempSQL);
        parseStruct.firstParenthesisPos=findnocase(" ( ",tempSQL);
        parseStruct.firstWHEREPos=len(tempSQL);
        if(left(trim(tempSQL), 5) EQ "show "){
            if(parseStruct.fromPos EQ 0){
                return arguments.sqlString;
            }
        }
        if(parseStruct.wherePos){
            parseStruct.firstWHEREPos=parseStruct.wherePos;
        }else if(parseStruct.groupByPos){
            parseStruct.firstWHEREPos=parseStruct.groupByPos;
        }else if(parseStruct.orderByPos){
            parseStruct.firstWHEREPos=parseStruct.orderByPos;
        }else if(parseStruct.orderByPos){
            parseStruct.firstWHEREPos=parseStruct.orderByPos;
        }else if(parseStruct.havingPos){
            parseStruct.firstWHEREPos=parseStruct.havingPos;
        }else if(parseStruct.limitPos){
            parseStruct.firstWHEREPos=parseStruct.limitPos;
        }
        parseStruct.lastWHEREPos=len(tempSQL);
        if(parseStruct.groupByPos){
            parseStruct.lastWHEREPos=parseStruct.groupByPos;
        }else if(parseStruct.orderByPos){
            parseStruct.lastWHEREPos=parseStruct.orderByPos;
        }else if(parseStruct.havingPos){
            parseStruct.lastWHEREPos=parseStruct.havingPos;
        }else if(parseStruct.limitPos){
            parseStruct.lastWHEREPos=parseStruct.limitPos;
        }
        parseStruct.setStatement="";
        if(parseStruct.setPos){
            if(parseStruct.wherePos){
                parseStruct.setStatement=mid(tempSQL, parseStruct.setPos+5, parseStruct.wherePos-(parseStruct.setPos+5));
            }else{
                parseStruct.setStatement=mid(tempSQL, parseStruct.setPos+5, len(tempSQL)-(parseStruct.setPos+5));
            }
        }
        if(parseStruct.wherePos){
            parseStruct.whereStatement=mid(tempSQL, parseStruct.wherePos+6, parseStruct.lastWHEREPos-(parseStruct.wherePos+6));
        }else{
            parseStruct.whereStatement="";
        }
        parseStruct.arrLeftJoin=arraynew(1);
        local.matching=true;
        local.curPos=1;
        while(local.matching){
            tableStruct=structnew();
            tableStruct.leftJoinPos=findnocase(" left join ",tempSQL, local.curPos);
            if(tableStruct.leftJoinPos EQ 0) break;
            tableStruct.onPos=findnocase(" on ",tempSQL, tableStruct.leftJoinPos+1);
            if(tableStruct.onPos EQ 0 or tableStruct.onPos GT parseStruct.firstWHEREPos){
                tableStruct.onPos=parseStruct.firstWHEREPos;
            }
            tableStruct.table=mid(tempSQL, tableStruct.leftJoinPos+11, tableStruct.onPos-(tableStruct.leftJoinPos+11));
			if(arguments.configStruct.identifierQuoteCharacter NEQ ""){
				tableStruct.table=trim(replace(tableStruct.table, arguments.configStruct.identifierQuoteCharacter,"","all"));
			}
            if(tableStruct.table CONTAINS " as "){
                local.stringPosition=findnocase(" as ",tableStruct.table);
                tableStruct.tableAlias=trim(mid(tableStruct.table, local.stringPosition+4, len(tableStruct.table)-(local.stringPosition+3)));
                tableStruct.table=trim(left(tableStruct.table,local.stringPosition-1));
            }else if(tableStruct.table CONTAINS " "){
                local.stringPosition=findnocase(" ",tableStruct.table);
                tableStruct.tableAlias=trim(mid(tableStruct.table, local.stringPosition+1, len(tableStruct.table)-(local.stringPosition)));
                tableStruct.table=trim(left(tableStruct.table,local.stringPosition-1));
            }else{
                tableStruct.table=trim(tableStruct.table);
                tableStruct.tableAlias=trim(tableStruct.table);
            }
			if(arguments.configStruct.enableTablePrefixing){
				if(findnocase(variables.tableSQLString,tableStruct.table) EQ 0){
					arrayappend(parseStruct.arrError, "All tables in queries must be generated with dbQuery.table(table, datasource); function. This table wasn't: "&tableStruct.table);
				}else{
					tableStruct.table=replacenocase(tableStruct.table,variables.tableSQLString,"");
					tableStruct.tableAlias=replacenocase(tableStruct.tableAlias,variables.tableSQLString,"");
				}
			}
            tableStruct.onstatement="";
            if(tableStruct.table DOES NOT CONTAIN "."){
                tableStruct.table=arguments.defaultDatabaseName&"."&tableStruct.table;
            }else{
                if(tableStruct.tableAlias CONTAINS "."){
                    tableStruct.tableAlias=trim(listgetat(tableStruct.tableAlias,2,"."));
                }
            }
            local.curPos=tableStruct.onPos+1;
            arrayappend(parseStruct.arrLeftJoin, tableStruct);
        }
		
		
        
        if(parseStruct.firstLeftJoinPos){
            parseStruct.endOfFromPos=parseStruct.firstLeftJoinPos;
        }else if(parseStruct.firstWHEREPos){
            parseStruct.endOfFromPos=parseStruct.firstWHEREPos;
        }else{
            parseStruct.endOfFromPos=len(tempSQL);
        }
        
        if(parseStruct.intoPos and (parseStruct.selectPos EQ 0 or parseStruct.selectPos GT parseStruct.intoPos)){
            if(parseStruct.setPos){
                tableStruct=structnew();
                tableStruct.type="into";
                tableStruct.table=mid(tempSQL, parseStruct.intoPos+5, parseStruct.setPos-(parseStruct.intoPos+5));
                tableStruct.tableAlias=tableStruct.table;
                arrayappend(parseStruct.arrTable, tableStruct);
            }else if(parseStruct.firstParenthesisPos){
                tableStruct=structnew();
                tableStruct.type="into";
                tableStruct.table=mid(tempSQL, parseStruct.intoPos+5, parseStruct.firstParenthesisPos-(parseStruct.intoPos+5));
                tableStruct.tableAlias=tableStruct.table;
                arrayappend(parseStruct.arrTable, tableStruct);
            }else{
                if(parseStruct.selectPos){
                    tableStruct=structnew();
                    tableStruct.type="into";
                    tableStruct.table=mid(tempSQL, parseStruct.intoPos+5, parseStruct.selectPos-(parseStruct.intoPos+5));
                    tableStruct.tableAlias=tableStruct.table;
                    arrayappend(parseStruct.arrTable, tableStruct);
                }
            }
        }
        if(parseStruct.fromPos){
            local.c2=mid(tempSQL, parseStruct.fromPos+5, parseStruct.endOfFromPos-(parseStruct.fromPos+5));
            local.c2=replacenocase(replacenocase(replacenocase(replacenocase(replace(replace(local.c2,")"," ","all"),"("," ","all"), " STRAIGHT_JOIN ", " , ","all"), " CROSS JOIN ", " , ","all"), " INNER JOIN ", " , ","all"), " JOIN ", " , ","all");
            local.arrT2=listtoarray(local.c2, ",");
            for(i=1;i LTE arraylen(local.arrT2);i++){
                local.arrT2[i]=trim(local.arrT2[i]);
                tableStruct=structnew();
                tableStruct.type="from";
                if(local.arrT2[i] CONTAINS " as "){
                    local.stringPosition=findnocase(" as ", local.arrT2[i]);
                    tableStruct.tableAlias=trim(mid(local.arrT2[i], local.stringPosition+4, len(local.arrT2[i])-(local.stringPosition+3)));
                    tableStruct.table=trim(left(local.arrT2[i],local.stringPosition-1));
                }else if(local.arrT2[i] CONTAINS " "){
                    local.stringPosition=findnocase(" ", local.arrT2[i]);
                    tableStruct.tableAlias=trim(mid(local.arrT2[i], local.stringPosition+1, len(local.arrT2[i])-(local.stringPosition)));
                    tableStruct.table=trim(left(local.arrT2[i],local.stringPosition-1));
                }else{
                    tableStruct.table=trim(local.arrT2[i]);
                    tableStruct.tableAlias=trim(local.arrT2[i]);
                }
				if(arguments.configStruct.enableTablePrefixing){
					if(findnocase(variables.tableSQLString,tableStruct.table) EQ 0){
						arrayappend(parseStruct.arrError, "All tables in queries must be generated with dbQuery.table(table, datasource); function. This table wasn't: "&tableStruct.table);
					}else{
						tableStruct.table=replacenocase(tableStruct.table,variables.tableSQLString,arguments.configStruct.identifierQuoteCharacter);
						tableStruct.tableAlias=replacenocase(tableStruct.tableAlias,variables.tableSQLString,arguments.configStruct.identifierQuoteCharacter);
					}
				}
                arrayappend(parseStruct.arrTable, tableStruct);
            }
        }
		
		
        for(i=1;i LTE arraylen(parseStruct.arrLeftJoin);i++){
            if(i EQ arraylen(parseStruct.arrLeftJoin)){
                local.np=parseStruct.firstWHEREPos;
            }else{
                local.np=parseStruct.arrLeftJoin[i+1].leftJoinPos;
            }
            if(local.np NEQ parseStruct.arrLeftJoin[i].onPos){
                parseStruct.arrLeftJoin[i].onstatement=mid(tempSQL, parseStruct.arrLeftJoin[i].onPos+4, local.np-(parseStruct.arrLeftJoin[i].onPos+4));
            }
        }
        for(i=1;i LTE arraylen(parseStruct.arrTable);i++){
			if(arguments.configStruct.identifierQuoteCharacter NEQ ""){
				parseStruct.arrTable[i].table=trim(replace(parseStruct.arrTable[i].table,arguments.configStruct.identifierQuoteCharacter,"","all"));
				parseStruct.arrTable[i].tableAlias=trim(replace(parseStruct.arrTable[i].tableAlias,arguments.configStruct.identifierQuoteCharacter,"","all"));
			}
            if(parseStruct.arrTable[i].table DOES NOT CONTAIN "."){
                parseStruct.arrTable[i].table=arguments.defaultDatabaseName&"."&parseStruct.arrTable[i].table;
            }else{
                if(parseStruct.arrTable[i].tableAlias CONTAINS "."){
                    parseStruct.arrTable[i].tableAlias=trim(listgetat(parseStruct.arrTable[i].tableAlias,2,"."));
                }
            }
        }
		parseStruct.defaultDatabaseName=arguments.defaultDatabaseName;
        parseStruct.sql=replace(arguments.sqlString, variables.tableSQLString,"","all");
		for(local.functionIndex in arguments.configStruct.parseSQLFunctionStruct){
			local.parseFunction=arguments.configStruct.parseSQLFunctionStruct[local.functionIndex];
			parseStruct=local.parseFunction(parseStruct);
		}
        if(arraylen(parseStruct.arrError) NEQ 0){
			throw(arraytolist(parseStruct.arrError, "<br />")&"<br /><br />SQL Statement<br />"&parseStruct.sql, "database");
        }
        return parseStruct.sql;
        </cfscript>
    </cffunction> 
    
    </cfoutput>
</cfcomponent>