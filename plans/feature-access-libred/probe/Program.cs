using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Common;
using System.IO;
using System.Linq;
using System.Reflection;

using LibRed.Data;

static class Program
{
	static void Main(string[] args)
	{
		var mode = args.Length > 0 ? args[0] : "signatures";

		switch (mode)
		{
			case "signatures": DumpSignatures(); break;
			case "smoke"     : Smoke(args.Length > 1 ? args[1] : ".accdb"); break;
			case "battery"   : Battery(args.Length > 1 ? args[1] : ".accdb"); break;
			case "schema"    : Schema(args.Length > 1 ? args[1] : ".accdb"); break;
			case "access-sql": AccessSql(args.Length > 1 ? args[1] : ".accdb"); break;
			case "ms-file"   : MsFile(args[1]); break;
			case "meta"      : Meta(args[1]); break;
			case "views"     : Views(args[1]); break;
			case "qname"     : QName(args[1]); break;
			case "ver"       : foreach (var f in args[1..]) Ver(f); break;
			case "script"    : Script(args[1], args[2]); break;
			default          : Console.WriteLine("unknown mode " + mode); break;
		}
	}

	static void DumpSignatures()
	{
		var types = new[] { "LibRed.Ado", "LibRed.Engine", "LibRed.Core", "LibRed.Sql" }
			.SelectMany(a => Assembly.Load(a).GetExportedTypes());

		foreach (var t in types.OrderBy(t => t.FullName))
		{
			if (t.IsEnum)
			{
				Console.WriteLine("ENUM " + t.FullName + " = " + string.Join(", ", Enum.GetNames(t)));
				continue;
			}

			Console.WriteLine("TYPE " + t.FullName + " : " + t.BaseType?.FullName);

			foreach (var m in t.GetMembers(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly))
			{
				if (m is MethodInfo mi)
				{
					if (mi.IsSpecialName) continue;
					Console.WriteLine("    " + (mi.IsStatic ? "static " : "") + Short(mi.ReturnType) + " " + mi.Name + "(" +
						string.Join(", ", mi.GetParameters().Select(p => Short(p.ParameterType) + " " + p.Name + (p.HasDefaultValue ? " = " + (p.DefaultValue ?? "null") : ""))) + ")");
				}
				else if (m is ConstructorInfo ci)
				{
					Console.WriteLine("    .ctor(" + string.Join(", ", ci.GetParameters().Select(p => Short(p.ParameterType) + " " + p.Name)) + ")");
				}
				else if (m is PropertyInfo pi)
				{
					Console.WriteLine("    prop " + Short(pi.PropertyType) + " " + pi.Name + " { " + (pi.CanRead ? "get; " : "") + (pi.CanWrite ? "set; " : "") + "}");
				}
				else if (m is FieldInfo fi)
				{
					Console.WriteLine("    field " + Short(fi.FieldType) + " " + fi.Name + (fi.IsLiteral ? " = " + fi.GetRawConstantValue() : ""));
				}
			}
		}
	}

	static string Short(Type t)
	{
		if (t == null) return "?";
		if (t.IsGenericType)
			return t.Name.Substring(0, t.Name.IndexOf('`')) + "<" + string.Join(", ", t.GetGenericArguments().Select(Short)) + ">";
		return t.Name;
	}

	static void Smoke(string ext)
	{
		var dir  = Path.Combine(Path.GetTempPath(), "libred-probe");
		Directory.CreateDirectory(dir);
		var file = Path.Combine(dir, "probe" + ext);

		if (File.Exists(file)) File.Delete(file);

		Console.WriteLine("file: " + file);

		Report("CreateDatabase", () =>
		{
			var mi   = typeof(LibRedConnection).GetMethod("CreateDatabase", BindingFlags.Public | BindingFlags.Static);
			var ps   = mi.GetParameters();
			var args = new object[ps.Length];

			for (var i = 0; i < ps.Length; i++)
			{
				var pt = ps[i].ParameterType;

				if      (pt == typeof(string)) args[i] = i == 0 ? file : null;
				else if (pt.IsEnum)            args[i] = Enum.Parse(pt, Enum.GetNames(pt).First(n => ext == ".accdb" ? n.Contains("Ace") || n.Contains("12") : n.Contains("4")));
				else                           args[i] = ps[i].HasDefaultValue ? ps[i].DefaultValue : (pt.IsValueType ? Activator.CreateInstance(pt) : null);
			}

			Console.WriteLine("     CreateDatabase(" + string.Join(", ", ps.Select((p, i) => Short(p.ParameterType) + " " + p.Name + "=" + (args[i] ?? "null"))) + ")");
			mi.Invoke(null, args);
			return "exists=" + File.Exists(file) + " size=" + new FileInfo(file).Length;
		});

		var cs = "Data Source=" + file;
		Console.WriteLine("connection string: " + cs);

		using var cn = new LibRedConnection(cs);
		Report("Open", () => { cn.Open(); return cn.State + " serverVersion=" + cn.ServerVersion + " database=" + cn.Database + " dataSource=" + cn.DataSource; });

		Exec(cn, "CREATE TABLE Probe (Id COUNTER NOT NULL PRIMARY KEY, Name VARCHAR(50), Num DOUBLE, Dec CURRENCY, D DATETIME, B BIT, G GUID, Bin LONGBINARY, Memo MEMO)");
		Exec(cn, "INSERT INTO Probe (Name, Num, Dec, D, B, G) VALUES ('a', 1.5, 2.25, #2026-01-02 03:04:05#, 1, {guid {11111111-1111-1111-1111-111111111111}})");

		Report("parameterized insert", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "INSERT INTO Probe (Name, Num) VALUES (?, ?)";
			var p1 = cmd.CreateParameter(); p1.ParameterName = "p1"; p1.Value = "b"; cmd.Parameters.Add(p1);
			var p2 = cmd.CreateParameter(); p2.ParameterName = "p2"; p2.Value = 3.5d; cmd.Parameters.Add(p2);
			return "rows=" + cmd.ExecuteNonQuery();
		});

		Report("named parameters", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "INSERT INTO Probe (Name, Num) VALUES (@name, @num)";
			var p1 = cmd.CreateParameter(); p1.ParameterName = "@name"; p1.Value = "c"; cmd.Parameters.Add(p1);
			var p2 = cmd.CreateParameter(); p2.ParameterName = "@num";  p2.Value = 4.5d; cmd.Parameters.Add(p2);
			return "rows=" + cmd.ExecuteNonQuery();
		});

		Report("identity", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT @@IDENTITY";
			return "value=" + cmd.ExecuteScalar();
		});

		Report("select", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT Id, Name, Num, Dec, D, B, G FROM Probe ORDER BY Id";
			using var rd = cmd.ExecuteReader();
			var n = 0;
			var cols = string.Join(", ", Enumerable.Range(0, rd.FieldCount).Select(i => rd.GetName(i) + ":" + rd.GetDataTypeName(i) + "/" + rd.GetFieldType(i).Name));
			while (rd.Read()) n++;
			return "rows=" + n + " cols=[" + cols + "]";
		});

		// SQL capability probes
		foreach (var sql in new[]
		{
			"SELECT TOP 1 Id FROM Probe",
			"SELECT COUNT(*) FROM Probe",
			"SELECT IIF(B, 1, 0) FROM Probe",
			"SELECT CASE WHEN Num > 1 THEN 'x' ELSE 'y' END FROM Probe",
			"SELECT COALESCE(Name, 'z') FROM Probe",
			"SELECT Id FROM Probe UNION SELECT Id FROM Probe",
			"SELECT * FROM (SELECT Id FROM Probe) AS T",
			"SELECT Id, ROW_NUMBER() OVER (ORDER BY Id) AS RN FROM Probe",
			"SELECT Id FROM Probe ORDER BY Id OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY",
			"SELECT p.Id FROM Probe p CROSS APPLY (SELECT TOP 1 Id AS X FROM Probe) AS q",
			"SELECT Name FROM Probe WHERE Name LIKE 'a%'",
			"SELECT Name FROM Probe WHERE Name LIKE '*a*'",
			"SELECT CDBL(Num) FROM Probe",
			"SELECT INT(Num) FROM Probe",
			"SELECT 1 FROM Probe WHERE Id IN (SELECT Id FROM Probe)",
			"SELECT Id FROM Probe AS p1 INNER JOIN Probe AS p2 ON p1.Id = p2.Id",
			"SELECT DISTINCT Name FROM Probe",
			"SELECT Name, COUNT(*) FROM Probe GROUP BY Name HAVING COUNT(*) > 0",
			"SELECT Id FROM Probe WHERE Id = ? OR 1 = 1",
		})
		{
			Report("sql: " + sql, () =>
			{
				using var cmd = cn.CreateCommand();
				cmd.CommandText = sql;
				if (sql.Contains('?'))
				{
					var p = cmd.CreateParameter(); p.Value = 1; cmd.Parameters.Add(p);
				}

				using var rd = cmd.ExecuteReader();
				var n = 0;
				while (rd.Read()) n++;
				return "rows=" + n;
			});
		}

		Report("GetSchema()", () => Dump(cn.GetSchema()));
		foreach (var coll in new[] { "Tables", "Columns", "Indexes", "ForeignKeys", "Views", "Procedures", "DataTypes", "MetaDataCollections" })
			Report("GetSchema(" + coll + ")", () => Dump(cn.GetSchema(coll)));

		Report("transaction commit", () =>
		{
			using var tr = cn.BeginTransaction();
			using var cmd = cn.CreateCommand();
			cmd.Transaction = tr;
			cmd.CommandText = "INSERT INTO Probe (Name) VALUES ('tx')";
			var n = cmd.ExecuteNonQuery();
			tr.Commit();
			return "rows=" + n;
		});

		Report("transaction rollback", () =>
		{
			using var tr = cn.BeginTransaction();
			using var cmd = cn.CreateCommand();
			cmd.Transaction = tr;
			cmd.CommandText = "INSERT INTO Probe (Name) VALUES ('rb')";
			cmd.ExecuteNonQuery();
			tr.Rollback();

			using var cmd2 = cn.CreateCommand();
			cmd2.CommandText = "SELECT COUNT(*) FROM Probe WHERE Name = 'rb'";
			return "remaining=" + cmd2.ExecuteScalar();
		});

		Report("DatabaseExists", () => LibRedConnection.DatabaseExists(cs).ToString());
		Report("HasUserTables", () => cn.HasUserTables().ToString());

		// pooling: the alpha.2 bug is reported as "the 65th query on one connection fails"
		Report("100 opens", () =>
		{
			for (var i = 0; i < 100; i++)
			{
				using var c = new LibRedConnection(cs);
				c.Open();
				using var cmd = c.CreateCommand();
				cmd.CommandText = "SELECT COUNT(*) FROM Probe";
				cmd.ExecuteScalar();
			}

			return "ok";
		});

		Report("200 queries on one connection", () =>
		{
			for (var i = 0; i < 200; i++)
			{
				using var cmd = cn.CreateCommand();
				cmd.CommandText = "SELECT COUNT(*) FROM Probe";
				cmd.ExecuteScalar();
			}

			return "ok";
		});
	}

	static void Battery(string ext)
	{
		var dir  = Path.Combine(Path.GetTempPath(), "libred-probe");
		Directory.CreateDirectory(dir);
		var file = Path.Combine(dir, "battery" + ext);

		if (File.Exists(file)) File.Delete(file);

		var version = ext == ".accdb" ? "Version12_2007" : "Version4";
		Console.WriteLine("=== " + ext + " / " + version);

		Report("CreateDatabase " + version, () =>
		{
			var mi = typeof(LibRedConnection).GetMethod("CreateDatabase", BindingFlags.Public | BindingFlags.Static);
			var ps = mi.GetParameters();
			mi.Invoke(null, new object[] { file, null, Enum.Parse(ps[2].ParameterType, version) });
			return "size=" + new FileInfo(file).Length;
		});

		Report("CreateDatabase Version3 (Access 97)", () =>
		{
			var f2 = Path.Combine(dir, "jet3.mdb");
			if (File.Exists(f2)) File.Delete(f2);
			var mi = typeof(LibRedConnection).GetMethod("CreateDatabase", BindingFlags.Public | BindingFlags.Static);
			var ps = mi.GetParameters();
			mi.Invoke(null, new object[] { f2, null, Enum.Parse(ps[2].ParameterType, "Version3") });
			return "size=" + new FileInfo(f2).Length;
		});

		var cs = "Data Source=" + file;
		using var cn = new LibRedConnection(cs);
		cn.Open();
		Console.WriteLine("ServerVersion=" + cn.ServerVersion);

		// DDL forms linq2db emits
		foreach (var ddl in new[]
		{
			"CREATE TABLE Parent (Id COUNTER NOT NULL CONSTRAINT PK_Parent PRIMARY KEY, Name VARCHAR(50) NULL)",
			"CREATE TABLE Child (Id INT NOT NULL, ParentId INT NULL, Val DECIMAL(18, 4) NULL, Ts DATETIME NULL, Flag BIT NOT NULL, Uid GUID NULL, Txt MEMO NULL, Bin LONGBINARY NULL, B BYTE NULL, S SMALLINT NULL, R SINGLE NULL, C CURRENCY NULL)",
			"ALTER TABLE Child ADD CONSTRAINT PK_Child PRIMARY KEY (Id)",
			"ALTER TABLE Child ADD CONSTRAINT FK_Child_Parent FOREIGN KEY (ParentId) REFERENCES Parent (Id)",
			"CREATE INDEX IX_Child_ParentId ON Child (ParentId)",
			"CREATE UNIQUE INDEX UX_Child_Val ON Child (Val)",
			"CREATE VIEW ChildView AS SELECT Id, ParentId FROM Child",
			"DROP INDEX UX_Child_Val ON Child",
		})
			Exec2(cn, ddl);

		Exec2(cn, "INSERT INTO Parent (Name) VALUES ('p1')");
		Exec2(cn, "INSERT INTO Child (Id, ParentId, Val, Ts, Flag) VALUES (1, 1, 12.3456, #2026-01-02 03:04:05#, 1)");

		// literals + wildcards + parameters
		Query(cn, "datetime literal", "SELECT Ts FROM Child WHERE Ts = #2026-01-02 03:04:05#");
		Query(cn, "datetime literal ISO", "SELECT Ts FROM Child WHERE Ts = {ts '2026-01-02 03:04:05'}");
		Query(cn, "guid literal braces", "SELECT Id FROM Child WHERE Uid = {guid {11111111-1111-1111-1111-111111111111}}");
		Query(cn, "guid literal string", "SELECT Id FROM Child WHERE Uid = '11111111-1111-1111-1111-111111111111'");
		Query(cn, "like percent", "SELECT Name FROM Parent WHERE Name LIKE 'p%'");
		Query(cn, "like star", "SELECT Name FROM Parent WHERE Name LIKE 'p*'");
		Query(cn, "like underscore", "SELECT Name FROM Parent WHERE Name LIKE 'p_'");
		Query(cn, "like question", "SELECT Name FROM Parent WHERE Name LIKE 'p?'");
		Query(cn, "like escape clause", "SELECT Name FROM Parent WHERE Name LIKE 'p~%' ESCAPE '~'");
		Query(cn, "like bracket escape", "SELECT Name FROM Parent WHERE Name LIKE 'p[%]'");
		Query(cn, "select without from", "SELECT 1");
		Query(cn, "select from dual-ish", "SELECT COUNT(*) FROM Parent");
		Query(cn, "top with parameter", "SELECT TOP @n Id FROM Child", ("@n", 1));
		Query(cn, "param reused twice", "SELECT Id FROM Child WHERE Id = @p OR Id = @p", ("@p", 1));
		Query(cn, "param no-at-prefix name", "SELECT Id FROM Child WHERE Id = @p1", ("p1", 1));
		Query(cn, "param decimal", "SELECT Id FROM Child WHERE Val = @v", ("@v", 12.3456m));
		Query(cn, "param guid null", "SELECT Id FROM Child WHERE Uid IS NULL");
		Query(cn, "top with ties", "SELECT TOP 1 WITH TIES Id FROM Child ORDER BY Id");
		Query(cn, "full join", "SELECT p.Id FROM Parent p FULL JOIN Child c ON p.Id = c.ParentId");
		Query(cn, "intersect", "SELECT Id FROM Child INTERSECT SELECT Id FROM Child");
		Query(cn, "except", "SELECT Id FROM Child EXCEPT SELECT Id FROM Child");
		Query(cn, "values source", "SELECT * FROM (VALUES (1), (2)) AS T(X)");
		Query(cn, "insert select", "INSERT INTO Parent (Name) SELECT Name FROM Parent");
		Query(cn, "select into", "SELECT Id INTO CopyTable FROM Child");
		Query(cn, "nested set op in exists", "SELECT Id FROM Child WHERE EXISTS (SELECT Id FROM Child UNION SELECT Id FROM Child)");
		Query(cn, "iif", "SELECT IIF(Flag, 'y', 'n') FROM Child");
		Query(cn, "switch", "SELECT SWITCH(Flag = 1, 'y', TRUE, 'n') FROM Child");
		Query(cn, "string fns", "SELECT MID(Name, 1, 1), INSTR(Name, '1'), LEN(Name), UCASE(Name), LCASE(Name), TRIM(Name) FROM Parent");
		Query(cn, "date fns", "SELECT DATEADD('d', 1, Ts), DATEDIFF('d', Ts, Ts), DATEPART('yyyy', Ts), NOW(), DATE() FROM Child");
		Query(cn, "math fns", "SELECT ABS(Val), INT(Val), FIX(Val), SGN(Val), SQR(9), EXP(1), LOG(2), ROUND(Val, 2) FROM Child");
		Query(cn, "cast/convert fns", "SELECT CINT(Val), CDBL(Val), CSTR(Val), CDATE('2026-01-02'), CBOOL(1) FROM Child");
		Query(cn, "concat &", "SELECT Name & '-x' FROM Parent");
		Query(cn, "concat +", "SELECT Name + '-x' FROM Parent");
		Query(cn, "null fns", "SELECT IIF(ISNULL(Name), 'n', 'y'), NZ(Name, 'z') FROM Parent");
		Query(cn, "coalesce/nullif", "SELECT COALESCE(Name, 'z'), NULLIF(Name, 'p1') FROM Parent");
		Query(cn, "cast syntax", "SELECT CAST(Val AS INT) FROM Child");
		Query(cn, "update from-less", "UPDATE Child SET Val = 1 WHERE Id = 1");
		Query(cn, "delete", "DELETE FROM CopyTable");
		Query(cn, "multi-statement", "SELECT 1; SELECT 2");

		// information schema
		foreach (var t in new[] { "TABLES", "COLUMNS", "VIEWS", "INDEXES", "TABLE_CONSTRAINTS", "KEY_COLUMN_USAGE", "REFERENTIAL_CONSTRAINTS", "CONSTRAINT_COLUMN_USAGE", "SCHEMATA", "ROUTINES" })
			Query(cn, "INFORMATION_SCHEMA." + t, "SELECT * FROM INFORMATION_SCHEMA." + t, dumpRows: true);

		foreach (var t in new[] { "MSysObjects", "MSysRelationships" })
			Query(cn, t, "SELECT * FROM " + t, dumpRows: true);
	}

	// Replay linq2db's own create-data script through LibRed, the way CreateData.RunScript does:
	// split on a "GO" divider line, drop the DROP statements' failures, execute the rest.
	static void Script(string scriptPath, string ext)
	{
		var file = Path.Combine(Path.GetTempPath(), "libred-probe", "script" + ext);
		if (File.Exists(file)) File.Delete(file);

		var mi = typeof(LibRedConnection).GetMethod("CreateDatabase", BindingFlags.Public | BindingFlags.Static);
		var ps = mi.GetParameters();
		mi.Invoke(null, new object[] { file, null, Enum.Parse(ps[2].ParameterType, ext == ".accdb" ? "Version12_2007" : "Version4") });

		using var cn = new LibRedConnection("Data Source=" + file);
		cn.Open();

		var text  = File.ReadAllText(scriptPath);
		var parts = text.Split(["\nGO\n", "\r\nGO\r\n"], StringSplitOptions.None);
		int ok = 0, dropFail = 0;
		var failures = new List<string>();

		foreach (var raw in parts)
		{
			var sql = raw.Trim();
			if (sql.Length == 0) continue;

			try
			{
				using var cmd = cn.CreateCommand();
				cmd.CommandText = sql;
				cmd.ExecuteNonQuery();
				ok++;
			}
			catch (Exception ex)
			{
				// CreateData swallows DROP failures on a fresh database by design
				if (sql.StartsWith("DROP", StringComparison.OrdinalIgnoreCase)) { dropFail++; continue; }

				failures.Add(sql.Split('\n')[0].Trim() + "  -->  " + ex.GetType().Name + ": " + ex.Message.Replace("\r", " ").Replace("\n", " "));
			}
		}

		Console.WriteLine("statements=" + parts.Length + " executed=" + ok + " dropFailures(expected)=" + dropFail + " realFailures=" + failures.Count);

		foreach (var f in failures)
			Console.WriteLine("  FAIL " + f);

		Query(cn, "tables after script", "SELECT TABLE_NAME FROM [INFORMATION_SCHEMA.TABLES] WHERE TABLE_TYPE = 'BASE TABLE'", dumpRows: true, dumpAll: true);
	}

	// Can LibRed read/write a database file produced by Microsoft's own engine (Jet/ACE)?
	static void MsFile(string source)
	{
		var work = Path.Combine(Path.GetTempPath(), "libred-probe", "ms-" + Path.GetFileName(source));
		Directory.CreateDirectory(Path.GetDirectoryName(work)!);
		File.Copy(source, work, overwrite: true);
		Console.WriteLine("=== " + source + " -> " + work + " (" + new FileInfo(work).Length + " bytes)");

		using var cn = new LibRedConnection("Data Source=" + work);

		Report("Open", () => { cn.Open(); return cn.State + " version=" + cn.ServerVersion; });

		if (cn.State != ConnectionState.Open)
			return;

		Report("HasUserTables", () => cn.HasUserTables().ToString());

		// SchemaProviderBase.GetDatabaseName/GetDataSourceName read these; AccessSchemaProviderBase reads both
		Report("Database / DataSource / ServerVersion", () => "Database=[" + cn.Database + "] DataSource=[" + cn.DataSource + "] ServerVersion=[" + cn.ServerVersion + "]");

		// AccessDmlService classifies table-not-found by exception; what does LibRed raise?
		Report("missing table (select)", () => Caught(cn, "SELECT * FROM [NoSuchTable]"));
		Report("missing table (drop)",   () => Caught(cn, "DROP TABLE [NoSuchTable]"));

		Query(cn, "tables", "SELECT TABLE_NAME, TABLE_TYPE FROM [INFORMATION_SCHEMA.TABLES]", dumpRows: true, dumpAll: true);
		Query(cn, "columns of first table", "SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH, IDENTITY_SEED FROM [INFORMATION_SCHEMA.COLUMNS]", dumpRows: true);
		Query(cn, "indexes", "SELECT * FROM [INFORMATION_SCHEMA.INDEXES]", dumpRows: true);
		Query(cn, "relations", "SELECT * FROM [INFORMATION_SCHEMA.RELATIONS]", dumpRows: true);
		Query(cn, "msysobjects", "SELECT Name, Type FROM MSysObjects WHERE Type = 1", dumpRows: true, dumpAll: true);

		Report("read every user table", () =>
		{
			var names = new List<string>();

			using (var cmd = cn.CreateCommand())
			{
				cmd.CommandText = "SELECT TABLE_NAME FROM [INFORMATION_SCHEMA.TABLES] WHERE TABLE_TYPE = 'BASE TABLE'";
				using var rd = cmd.ExecuteReader();
				while (rd.Read()) names.Add(rd.GetString(0));
			}

			var ok = 0;
			var bad = new List<string>();

			foreach (var n in names)
			{
				try
				{
					using var cmd = cn.CreateCommand();
					cmd.CommandText = "SELECT * FROM [" + n + "]";
					using var rd = cmd.ExecuteReader();
					var rows = 0;
					while (rd.Read())
					{
						for (var i = 0; i < rd.FieldCount; i++) { if (!rd.IsDBNull(i)) _ = rd.GetValue(i); }

						rows++;
					}

					ok++;
				}
				catch (Exception ex)
				{
					bad.Add(n + ": " + ex.GetType().Name + " " + ex.Message.Replace("\r", " ").Replace("\n", " "));
				}
			}

			return "readable=" + ok + "/" + names.Count + (bad.Count > 0 ? "\n     FAILED: " + string.Join("\n     ", bad) : "");
		});

		Report("write into an MS-created table", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "CREATE TABLE [LibRedProbe] ([Id] INT NOT NULL, [Name] VARCHAR(20) NULL)";
			cmd.ExecuteNonQuery();

			using var ins = cn.CreateCommand();
			ins.CommandText = "INSERT INTO [LibRedProbe] ([Id], [Name]) VALUES (1, 'x')";
			var n = ins.ExecuteNonQuery();

			using var sel = cn.CreateCommand();
			sel.CommandText = "SELECT COUNT(*) FROM [LibRedProbe]";
			return "inserted=" + n + " count=" + sel.ExecuteScalar();
		});
	}

	// The SQL shapes linq2db's Access builders actually emit (per the AccessSqlBuilderBase /
	// AccessSqlOptimizer / AccessSqlExpressionConvertVisitor / AccessMemberTranslator inventory).
	static void AccessSql(string ext)
	{
		var dir  = Path.Combine(Path.GetTempPath(), "libred-probe");
		Directory.CreateDirectory(dir);
		var file = Path.Combine(dir, "accesssql" + ext);

		if (File.Exists(file)) File.Delete(file);

		var mi = typeof(LibRedConnection).GetMethod("CreateDatabase", BindingFlags.Public | BindingFlags.Static);
		var ps = mi.GetParameters();
		mi.Invoke(null, new object[] { file, null, Enum.Parse(ps[2].ParameterType, ext == ".accdb" ? "Version12_2007" : "Version4") });

		using var cn = new LibRedConnection("Data Source=" + file);
		cn.Open();

		Exec2(cn, "CREATE TABLE [Parent] ([Id] COUNTER NOT NULL CONSTRAINT [PK_Parent] PRIMARY KEY, [Name] VARCHAR(50) NULL, [Uid] GUID NULL, [Num] DOUBLE NULL, [Dec] DECIMAL(18, 4) NULL, [Ts] DATETIME NULL)");
		Exec2(cn, "CREATE TABLE [Child] ([Id] INT NOT NULL, [ParentId] INT NULL, [Name] VARCHAR(50) NULL)");
		Exec2(cn, "INSERT INTO [Parent] ([Name], [Num], [Dec], [Ts]) VALUES ('p1', 1.5, 2.25, #2026-01-02 03:04:05#)");
		Exec2(cn, "INSERT INTO [Child] ([Id], [ParentId], [Name]) VALUES (1, 1, 'c1')");

		// identity retrieval + reset (AccessSqlBuilderBase CommandCount/BuildCommand)
		Query(cn, "identity select", "SELECT @@IDENTITY", dumpRows: true);
		Exec2(cn, "ALTER TABLE [Parent] ALTER COLUMN [Id] COUNTER(1, 1)");

		// NULL column typization + CVar/CSng casts (AccessSqlBuilderBase / AccessSqlOptimizer.WrapParameters)
		Query(cn, "IIF(False, CVar(NULL), NULL)", "SELECT IIF(1 = 0, CVar(NULL), NULL) AS [c1] FROM [Parent]");
		Query(cn, "CVar param wrap", "SELECT CVar(@p) AS [c1] FROM [Parent]", ("@p", 1));
		Query(cn, "CSng cast", "SELECT CSng(@p) AS [c1] FROM [Parent]", ("@p", 1.5d));
		Query(cn, "CVar of column", "SELECT CVar([Num]) FROM [Parent]");

		// IS DISTINCT FROM emulation
		Query(cn, "IsDistinct emulation", "SELECT IIF([Name] = 'p1' OR [Name] IS NULL AND 'p1' IS NULL, 0, 1) FROM [Parent]");

		// TOP forms
		Query(cn, "TOP n", "SELECT TOP 1 [Id] FROM [Parent]");
		Query(cn, "TOP n PERCENT", "SELECT TOP 50 PERCENT [Id] FROM [Parent]");

		// joins: Access requires parenthesized nested joins; WrapJoinCondition wraps ON in ()
		Query(cn, "parenthesized nested join", "SELECT [p].[Id] FROM ([Parent] [p] INNER JOIN [Child] [c] ON ([p].[Id] = [c].[ParentId])) LEFT JOIN [Child] [c2] ON ([p].[Id] = [c2].[ParentId])");
		Query(cn, "comma join + WHERE", "SELECT [p].[Id] FROM [Parent] [p], [Child] [c] WHERE [p].[Id] = [c].[ParentId]");
		Query(cn, "left join constant nullability", "SELECT [c].[Id], 1 AS [const] FROM [Parent] [p] LEFT JOIN [Child] [c] ON ([p].[Id] = [c].[ParentId] AND 1 = 0)");

		// EXISTS/IN rewritten to COUNT(*) comparisons by AccessSqlOptimizer.CorrectExistsAndIn
        Query(cn, "count-based exists", "SELECT [p].[Id] FROM [Parent] [p] WHERE (SELECT COUNT(*) FROM [Child] [c] WHERE [c].[ParentId] = [p].[Id]) > 0");

		// UPDATE / DELETE shapes
		Exec2(cn, "UPDATE [Parent] SET [Name] = 'p2' WHERE [Id] = 1");
		Query(cn, "UPDATE ... FROM (Access style)", "UPDATE [Parent] [p] INNER JOIN [Child] [c] ON ([p].[Id] = [c].[ParentId]) SET [p].[Name] = 'p3'");
		Query(cn, "DELETE with join", "DELETE [p].* FROM [Parent] [p] WHERE [p].[Id] = 999");

		// multi-row insert (AccessBulkCopy MultipleRows; IsValuesSyntaxSupported = false)
		Query(cn, "insert ... select union all", "INSERT INTO [Child] ([Id], [ParentId], [Name]) SELECT 2, 1, 'c2' FROM [Parent] UNION ALL SELECT 3, 1, 'c3' FROM [Parent]");
		Query(cn, "insert ... values multi-row", "INSERT INTO [Child] ([Id], [ParentId], [Name]) VALUES (4, 1, 'c4'), (5, 1, 'c5')");

		// functions AccessSqlExpressionConvertVisitor / AccessMemberTranslator emit
		Query(cn, "LCase/UCase/Len", "SELECT LCASE([Name]), UCASE([Name]), LEN([Name]) FROM [Parent]");
		Query(cn, "InStr 4-arg", "SELECT INSTR(1, [Name], 'p', 1) FROM [Parent]");
		Query(cn, "InStr binary compare", "SELECT INSTR(1, [Name], 'p', 0) FROM [Parent]");
		Query(cn, "MOD operator", "SELECT [Id] MOD 2 FROM [Parent]");
		Query(cn, "BAND/BOR", "SELECT [Id] BAND 1, [Id] BOR 2 FROM [Parent]");
		Query(cn, "power operator", "SELECT [Num] ^ 2 FROM [Parent]");
		Query(cn, "String(n, c) + LPad", "SELECT STRING(3, '0') & [Name] FROM [Parent]");
		Query(cn, "Mid/CStr guid", "SELECT LCASE(MID(CSTR([Uid]), 2, 36)) FROM [Parent]");
		Query(cn, "IsNull()", "SELECT IIF(ISNULL([Name]), 1, 0) FROM [Parent]");
		Query(cn, "LTrim", "SELECT LTRIM([Name]) FROM [Parent]");
		Query(cn, "DateSerial", "SELECT DATESERIAL(2026, 1, 2) FROM [Parent]");
		Query(cn, "TimeValue/DateValue", "SELECT TIMEVALUE([Ts]), DATEVALUE([Ts]) FROM [Parent]");
		Query(cn, "CAST(x AS Date)", "SELECT CAST([Ts] AS Date) FROM [Parent]");
		Query(cn, "CDate/CStr/CBool/CInt/CDbl", "SELECT CDATE('2026-01-02'), CSTR([Num]), CBOOL(1), CINT([Num]), CDBL([Num]) FROM [Parent]");
		Query(cn, "Round/Int/Fix/Abs/Sgn", "SELECT ROUND([Num], 1), INT([Num]), FIX([Num]), ABS([Num]), SGN([Num]) FROM [Parent]");
		Query(cn, "Now()", "SELECT NOW() FROM [Parent]");
		Query(cn, "DatePart", "SELECT DATEPART('yyyy', [Ts]), DATEPART('q', [Ts]), DATEPART('ww', [Ts]) FROM [Parent]");
		Query(cn, "DateAdd/DateDiff", "SELECT DATEADD('m', 1, [Ts]), DATEDIFF('d', [Ts], [Ts]) FROM [Parent]");
		Query(cn, "string concat +", "SELECT [Name] + 'x' FROM [Parent]");
		Query(cn, "chr concat", "SELECT [Name] + CHR(65) FROM [Parent]");
		Query(cn, "hex binary literal", "SELECT 0x0102 FROM [Parent]");
		Query(cn, "WITH OWNERACCESS OPTION", "SELECT [Id] FROM [Parent] WITH OWNERACCESS OPTION");

		// GUID literal handling
		Report("guid roundtrip via parameter", () =>
		{
			using var up = cn.CreateCommand();
			up.CommandText = "UPDATE [Parent] SET [Uid] = @g WHERE [Id] = 1";
			var p = up.CreateParameter(); p.ParameterName = "@g"; p.Value = new Guid("11111111-1111-1111-1111-111111111111"); up.Parameters.Add(p);
			up.ExecuteNonQuery();

			using var q = cn.CreateCommand();
			q.CommandText = "SELECT COUNT(*) FROM [Parent] WHERE [Uid] = '11111111-1111-1111-1111-111111111111'";
			var byString = q.ExecuteScalar();

			using var q2 = cn.CreateCommand();
			q2.CommandText = "SELECT COUNT(*) FROM [Parent] WHERE [Uid] = @g";
			var p2 = q2.CreateParameter(); p2.ParameterName = "@g"; p2.Value = new Guid("11111111-1111-1111-1111-111111111111"); q2.Parameters.Add(p2);
			var byParam = q2.ExecuteScalar();

			using var q3 = cn.CreateCommand();
			q3.CommandText = "SELECT [Uid] FROM [Parent] WHERE [Id] = 1";
			var read = q3.ExecuteScalar();

			return "byStringLiteral=" + byString + " byParameter=" + byParam + " read=" + read + " (" + read?.GetType().Name + ")";
		});

		// the literal form the BASE AccessMappingSchema emits ('{guid:B}', braced) vs the ODBC/OleDb overrides
		Query(cn, "guid braced string literal", "SELECT COUNT(*) FROM [Parent] WHERE [Uid] = '{11111111-1111-1111-1111-111111111111}'");
		Query(cn, "guid unbraced string literal", "SELECT COUNT(*) FROM [Parent] WHERE [Uid] = '11111111-1111-1111-1111-111111111111'");

		Report("guid braced literal returns the row", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT COUNT(*) FROM [Parent] WHERE [Uid] = '{11111111-1111-1111-1111-111111111111}'";
			var braced = cmd.ExecuteScalar();

			using var cmd2 = cn.CreateCommand();
			cmd2.CommandText = "SELECT COUNT(*) FROM [Parent] WHERE [Uid] = '11111111-1111-1111-1111-111111111111'";
			return "braced=" + braced + " unbraced=" + cmd2.ExecuteScalar();
		});

		// the date-truncation shape AccessSqlExpressionConvertVisitor.ConvertConversion actually emits
		Query(cn, "IIF null-guarded DateValue", "SELECT IIF([Ts] IS NOT NULL, DateValue([Ts]), NULL) FROM [Parent]");
		Query(cn, "IIF null-guarded TimeValue", "SELECT IIF([Ts] IS NOT NULL, TimeValue([Ts]), NULL) FROM [Parent]");
		Query(cn, "IIF null-guarded CDate", "SELECT IIF([Name] IS NOT NULL, CDate([Name]), NULL) FROM [Parent] WHERE 1 = 0");
		Query(cn, "IIF null-guarded CStr", "SELECT IIF([Num] IS NOT NULL, CStr([Num]), NULL) FROM [Parent]");
		Query(cn, "IIF null-guarded CBool", "SELECT IIF([Num] IS NOT NULL, CBool([Num]), NULL) FROM [Parent]");

		// the bare-REFERENCES form TestBase.Identity.cs re-adds after an identity reset
		Report("bare REFERENCES (TestBase.Identity shape)", () =>
		{
			using var drop = cn.CreateCommand();
			drop.CommandText = "CREATE TABLE [IdChild] ([Id] INT NOT NULL CONSTRAINT PK_IdChild PRIMARY KEY, [ParentId] INT NULL)";
			drop.ExecuteNonQuery();

			using var cmd = cn.CreateCommand();
			cmd.CommandText = "ALTER TABLE [IdChild] ADD CONSTRAINT FK_IdChild FOREIGN KEY (ParentId) REFERENCES [Parent] ON UPDATE CASCADE ON DELETE CASCADE";
			cmd.ExecuteNonQuery();
			return "accepted";
		});

		// AccessDataProvider.SetCharField keys on the DRIVER's type name ("DBTYPE_WCHAR" / "CHAR").
		// What does LibRed report per Access store type?
		Report("GetDataTypeName per store type", () =>
		{
			using var ddl = cn.CreateCommand();
			ddl.CommandText = "CREATE TABLE [TypeNames] ([C] CHAR(1) NULL, [VC] VARCHAR(50) NULL, [M] MEMO NULL, [I] INT NULL, [D] DOUBLE NULL, [CU] CURRENCY NULL, [DEC] DECIMAL(18, 4) NULL, [B] BIT NULL, [G] GUID NULL, [BIN] LONGBINARY NULL, [DT] DATETIME NULL, [BY] BYTE NULL, [S] SMALLINT NULL, [SI] SINGLE NULL)";
			ddl.ExecuteNonQuery();

			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT * FROM [TypeNames]";
			using var rd = cmd.ExecuteReader();
			return string.Join(", ", Enumerable.Range(0, rd.FieldCount).Select(i => rd.GetName(i) + "=" + rd.GetDataTypeName(i)));
		});

		Query(cn, "INFORMATION_SCHEMA store types", "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH FROM [INFORMATION_SCHEMA.COLUMNS] WHERE TABLE_NAME = 'TypeNames'", dumpRows: true, dumpAll: true);

		// does LibRed pad a fixed-width CHAR on read? (that is what SetCharField's TrimEnd exists for)
		Report("CHAR padding", () =>
		{
			using var ddl = cn.CreateCommand();
			ddl.CommandText = "CREATE TABLE [CharPad] ([C10] CHAR(10) NULL, [C1] CHAR(1) NULL)";
			ddl.ExecuteNonQuery();

			using var ins = cn.CreateCommand();
			ins.CommandText = "INSERT INTO [CharPad] ([C10], [C1]) VALUES ('ab', 'x')";
			ins.ExecuteNonQuery();

			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT [C10], [C1] FROM [CharPad]";
			using var rd = cmd.ExecuteReader();
			rd.Read();
			return "C10=[" + rd.GetString(0) + "] len=" + rd.GetString(0).Length + "  C1=[" + rd.GetString(1) + "] len=" + rd.GetString(1).Length;
		});

		// NULL ordering (DefaultNullsOrdering = Smallest)
		Report("null ordering", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT [Name] FROM [Child] ORDER BY [Name]";
			using var rd = cmd.ExecuteReader();
			var vals = new List<string>();
			while (rd.Read()) vals.Add(rd.IsDBNull(0) ? "<null>" : rd.GetString(0));
			return string.Join(",", vals);
		});

		// parameter count ceiling (AccessBulkCopy caps at 767 parameters / 64 000 chars)
		foreach (var count in new[] { 255, 767, 1000, 5000 })
		{
			var n = count;
			Report("parameters x" + n, () =>
			{
				using var cmd = cn.CreateCommand();
				var sb = new System.Text.StringBuilder("SELECT COUNT(*) FROM [Parent] WHERE [Id] IN (");

				for (var i = 0; i < n; i++)
				{
					if (i > 0) sb.Append(", ");
					sb.Append("@p").Append(i);
					var p = cmd.CreateParameter();
					p.ParameterName = "@p" + i;
					p.Value         = i;
					cmd.Parameters.Add(p);
				}

				sb.Append(')');
				cmd.CommandText = sb.ToString();
				return "ok len=" + cmd.CommandText.Length + " -> " + cmd.ExecuteScalar();
			});
		}
	}

	static void Schema(string ext)
	{
		var file = Path.Combine(Path.GetTempPath(), "libred-probe", "battery" + ext);
		Console.WriteLine("=== schema over " + file);

		using var cn = new LibRedConnection("Data Source=" + file);
		cn.Open();

		Query(cn, "MSysObjects names", "SELECT Name, Type, ParentId, Flags FROM MSysObjects", dumpRows: true, dumpAll: true);

		foreach (var t in new[] { "MSysColumns", "MSysIndexes", "MSysIndexColumns", "MSysQueries", "MSysACEs", "MSysComplexColumns" })
			Query(cn, t, "SELECT * FROM " + t, dumpRows: true);

		foreach (var t in new[] { "TABLES", "COLUMNS", "VIEWS", "INDEXES", "TABLE_CONSTRAINTS", "KEY_COLUMN_USAGE", "REFERENTIAL_CONSTRAINTS" })
		{
			Query(cn, "[INFORMATION_SCHEMA." + t + "]", "SELECT * FROM [INFORMATION_SCHEMA." + t + "]", dumpRows: true);
			Query(cn, "INFORMATION_SCHEMA_" + t, "SELECT * FROM INFORMATION_SCHEMA_" + t, dumpRows: true);
		}

		Report("InformationSchema probe", () =>
		{
			var isType = Assembly.Load("LibRed.Engine").GetType("LibRed.Engine.Schema.InformationSchema");
			var isIs   = isType.GetMethod("IsInformationSchema");
			var colsOf = isType.GetMethod("ColumnsOf");
			var res    = "";

			var names = new[]
			{
				"TABLES", "COLUMNS", "VIEWS", "INDEXES", "INDEX_COLUMNS", "INDEXCOLUMNS", "CONSTRAINTS", "TABLE_CONSTRAINTS",
				"KEY_COLUMN_USAGE", "REFERENTIAL_CONSTRAINTS", "FOREIGN_KEYS", "RELATIONSHIPS", "RELATIONS", "PROCEDURES",
				"ROUTINES", "QUERIES", "PARAMETERS", "SCHEMATA", "PRIMARY_KEYS", "KEYS", "STATISTICS", "SEQUENCES",
			}.Select(n => "INFORMATION_SCHEMA." + n);

			foreach (var n in names)
			{
				var ok = (bool)isIs.Invoke(null, new object[] { n });
				var cs = ok ? (System.Collections.IEnumerable)colsOf.Invoke(null, new object[] { n }) : null;
				res += "\n     " + n + " -> " + ok + (cs != null ? " [" + string.Join(",", cs.Cast<object>()) + "]" : "");
			}

			return res;
		});

		Report("reader.GetSchemaTable()", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT * FROM Child WHERE 1 = 0";
			using var rd = cmd.ExecuteReader();
			var dt = rd.GetSchemaTable();
			return Dump(dt);
		});

		Report("reader.GetColumnSchema()", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT * FROM Child WHERE 1 = 0";
			using var rd = cmd.ExecuteReader();
			var cols = ((System.Data.Common.IDbColumnSchemaGenerator)rd).GetColumnSchema();
			return "cols=" + string.Join(", ", cols.Select(c => c.ColumnName + ":" + c.DataTypeName + "/" + c.DataType?.Name + " null=" + c.AllowDBNull + " size=" + c.ColumnSize));
		});

		Report("reader metadata on empty select", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT * FROM Child WHERE 1 = 0";
			using var rd = cmd.ExecuteReader();
			return string.Join(", ", Enumerable.Range(0, rd.FieldCount).Select(i => rd.GetName(i) + ":" + rd.GetDataTypeName(i) + "/" + rd.GetFieldType(i).Name));
		});
	}

	static void Exec2(DbConnection cn, string sql)
	{
		Report(Trim(sql), () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = sql;
			return "rows=" + cmd.ExecuteNonQuery();
		});
	}

	static string Trim(string s) => s.Length <= 70 ? s : s.Substring(0, 70) + "…";

	// metadata shapes the linq2db schema provider will read, against a Microsoft-created file
	static void Meta(string file)
	{
		Console.WriteLine("=== meta over " + file);

		using var cn = new LibRedConnection("Data Source=" + file);
		cn.Open();

		Query(cn, "TABLES"       , "SELECT * FROM [INFORMATION_SCHEMA.TABLES]"       , dumpRows: true, dumpAll: true);
		Query(cn, "COLUMNS"      , "SELECT * FROM [INFORMATION_SCHEMA.COLUMNS]"      , dumpRows: true, dumpAll: true);
		Query(cn, "INDEXES"      , "SELECT * FROM [INFORMATION_SCHEMA.INDEXES]"      , dumpRows: true, dumpAll: true);
		Query(cn, "INDEX_COLUMNS", "SELECT * FROM [INFORMATION_SCHEMA.INDEX_COLUMNS]", dumpRows: true, dumpAll: true);
		Query(cn, "RELATIONS"    , "SELECT * FROM [INFORMATION_SCHEMA.RELATIONS]"    , dumpRows: true, dumpAll: true);
		Query(cn, "MSysRelationships", "SELECT * FROM MSysRelationships"             , dumpRows: true, dumpAll: true);
		Query(cn, "MSysObjects"      , "SELECT Name, Type, Flags FROM MSysObjects"   , dumpRows: true, dumpAll: true);

		// ordering/filtering forms the schema provider would use
		Query(cn, "TABLES ordered"    , "SELECT TABLE_NAME, TABLE_TYPE FROM [INFORMATION_SCHEMA.TABLES] ORDER BY TABLE_NAME");
		Query(cn, "COLUMNS filtered"  , "SELECT COLUMN_NAME FROM [INFORMATION_SCHEMA.COLUMNS] WHERE TABLE_NAME = 'Person'", dumpRows: true, dumpAll: true);
		Query(cn, "COLUMNS param"     , "SELECT COLUMN_NAME FROM [INFORMATION_SCHEMA.COLUMNS] WHERE TABLE_NAME = @t", ("@t", "Person"), dumpRows: true, dumpAll: true);
		Query(cn, "INDEXES join"      , "SELECT i.TABLE_NAME, i.INDEX_NAME, c.COLUMN_NAME FROM [INFORMATION_SCHEMA.INDEXES] i INNER JOIN [INFORMATION_SCHEMA.INDEX_COLUMNS] c ON (i.INDEX_NAME = c.INDEX_NAME) WHERE i.INDEX_TYPE = 'PRIMARY'", dumpRows: true, dumpAll: true);
		Query(cn, "MSysObjects views" , "SELECT Name FROM MSysObjects WHERE Type = 5", dumpRows: true, dumpAll: true);

		// the only Jet-vs-Ace behavioural split in linq2db's Access translators
		Query(cn, "REPLACE"           , "SELECT REPLACE([FirstName], 'o', 'X') FROM [Person]", dumpRows: true);
	}

	// can stored Access queries be surfaced as views, and where does their column metadata come from?
	static void Views(string file)
	{
		Console.WriteLine("=== views over " + file);

		using var cn = new LibRedConnection("Data Source=" + file);
		cn.Open();

		// does INFORMATION_SCHEMA know anything about a query?
		Query(cn, "COLUMNS for a query", "SELECT * FROM [INFORMATION_SCHEMA.COLUMNS] WHERE TABLE_NAME = 'Person_SelectAll'", dumpRows: true, dumpAll: true);
		Query(cn, "TABLES for a query" , "SELECT * FROM [INFORMATION_SCHEMA.TABLES] WHERE TABLE_NAME = 'Person_SelectAll'", dumpRows: true, dumpAll: true);

		// reading a query as a table source: parameterless SELECT, parameterised SELECT, name with a space
		foreach (var q in new[] { "Person_SelectAll", "Patient_SelectAll", "Scalar_DataReader", "Person_SelectByKey", "Person_SelectByName", "LinqDataTypes Query" })
		{
			Query(cn, "empty-set read [" + q + "]", "SELECT * FROM [" + q + "] WHERE 1 = 0", dumpRows: true, dumpAll: true);
			SchemaOnly(cn, q);
		}

		// MSysQueries: does it hold the output column list?
		Query(cn, "MSysQueries", "SELECT * FROM MSysQueries", dumpRows: true);

		// the algorithm the schema provider will run: Flags low byte selects row-returning query types,
		// then an empty-set probe keeps only what LibRed can actually bind
		var candidates = new List<(string Name, int Flags)>();

		using (var cmd = cn.CreateCommand())
		{
			cmd.CommandText = "SELECT Name, Flags FROM MSysObjects WHERE Type = 5";
			using var rd = cmd.ExecuteReader();
			while (rd.Read())
				candidates.Add((rd.GetString(0), rd.GetInt32(1)));
		}

		foreach (var (name, flags) in candidates)
		{
			var kind    = flags & 0xF0;
			var returns = kind is 0x00 or 0x10 or 0x80;
			var hidden  = name.StartsWith("~", StringComparison.Ordinal);
			var verdict = !returns ? "SKIP action/ddl kind=0x" + kind.ToString("X2") : hidden ? "SKIP hidden" : null;

			if (verdict != null)
			{
				Console.WriteLine("----  [" + name + "] flags=0x" + flags.ToString("X8") + " -> " + verdict);
				continue;
			}

			try
			{
				using var cmd = cn.CreateCommand();
				cmd.CommandText = "SELECT * FROM [" + name + "] WHERE 1 = 0";
				using var rd = cmd.ExecuteReader();
				Console.WriteLine("VIEW  [" + name + "] flags=0x" + flags.ToString("X8") + " -> cols=[" +
					string.Join(",", Enumerable.Range(0, rd.FieldCount).Select(i => rd.GetName(i) + ":" + rd.GetFieldType(i).Name)) + "]");
			}
			catch (Exception ex)
			{
				Console.WriteLine("----  [" + name + "] flags=0x" + flags.ToString("X8") + " -> DROP " + ex.GetType().Name);
			}
		}
	}

	static void Ver(string file)
	{
		Report("open " + Path.GetFileName(file), () =>
		{
			using var cn = new LibRedConnection("Data Source=" + file);
			cn.Open();
			return "serverVersion=" + cn.ServerVersion + " hasUserTables=" + cn.HasUserTables() + " bytes=" + new FileInfo(file).Length;
		});
	}

	// does a database-qualified table name work, as TestUtils.GetDatabaseName assumes for OLE DB?
	static void QName(string file)
	{
		Console.WriteLine("=== qname over " + file);

		using var cn = new LibRedConnection("Data Source=" + file);
		cn.Open();

		var noExt = Path.Combine(Path.GetDirectoryName(file), Path.GetFileNameWithoutExtension(file));

		Query(cn, "unqualified"     , "SELECT COUNT(*) FROM [Person]"                     , dumpRows: true);
		Query(cn, "db-qualified"    , "SELECT COUNT(*) FROM [" + file  + "].[Person]"     , dumpRows: true);
		Query(cn, "db-qualified noext", "SELECT COUNT(*) FROM [" + noExt + "].[Person]"   , dumpRows: true);
		Query(cn, "db.schema.table" , "SELECT COUNT(*) FROM [" + file  + "]..[Person]"    , dumpRows: true);
		Query(cn, "IN clause"       , "SELECT COUNT(*) FROM [Person] IN '" + file + "'"   , dumpRows: true);
	}

	static void SchemaOnly(DbConnection cn, string q)
	{
		Report("SchemaOnly [" + q + "]", () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = "SELECT * FROM [" + q + "]";
			using var rd = cmd.ExecuteReader(CommandBehavior.SchemaOnly);
			var cols = string.Join(",", Enumerable.Range(0, rd.FieldCount).Select(i => rd.GetName(i) + ":" + rd.GetFieldType(i).Name));
			var n = 0;
			while (rd.Read()) n++;
			return "cols=[" + cols + "] rowsRead=" + n;
		});
	}

	static void Query(DbConnection cn, string label, string sql, (string, object) param = default, bool dumpRows = false, bool dumpAll = false)
	{
		Report(label + " | " + Trim(sql), () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = sql;

			if (param.Item1 != null)
			{
				var p = cmd.CreateParameter();
				p.ParameterName = param.Item1;
				p.Value         = param.Item2;
				cmd.Parameters.Add(p);
			}

			using var rd = cmd.ExecuteReader();
			var n    = 0;
			var cols = string.Join(",", Enumerable.Range(0, rd.FieldCount).Select(i => rd.GetName(i) + ":" + rd.GetFieldType(i).Name));
			var first = "";

			while (rd.Read())
			{
				if (dumpRows && (dumpAll || n < 3))
					first += " {" + string.Join("|", Enumerable.Range(0, rd.FieldCount).Select(i => rd.IsDBNull(i) ? "<null>" : rd.GetValue(i).ToString())) + "}";
				n++;
			}

			return "rows=" + n + (dumpRows ? " cols=[" + cols + "]" + first : "");
		});
	}

	static string Caught(DbConnection cn, string sql)
	{
		try
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = sql;
			using var rd = cmd.ExecuteReader();
			while (rd.Read()) { }

			return "no exception (!)";
		}
		catch (Exception ex)
		{
			var number = ex.GetType().GetProperty("Number")?.GetValue(ex);
			return ex.GetType().FullName + " Number=" + (number?.ToString() ?? "<none>") + " message=" + ex.Message.Replace("\r", " ").Replace("\n", " ");
		}
	}

	static string Dump(DataTable dt)
	{
		if (dt == null) return "<null>";
		return dt.TableName + " rows=" + dt.Rows.Count + " cols=[" + string.Join(", ", dt.Columns.Cast<DataColumn>().Select(c => c.ColumnName)) + "]";
	}

	static void Exec(DbConnection cn, string sql)
	{
		Report("ddl/dml: " + sql.Substring(0, Math.Min(60, sql.Length)), () =>
		{
			using var cmd = cn.CreateCommand();
			cmd.CommandText = sql;
			return "rows=" + cmd.ExecuteNonQuery();
		});
	}

	static void Report(string what, Func<string> action)
	{
		try
		{
			Console.WriteLine("OK   " + what + " -> " + action());
		}
		catch (Exception ex)
		{
			Console.WriteLine("FAIL " + what + " -> " + ex.GetType().Name + ": " + ex.Message.Replace("\r", " ").Replace("\n", " "));
		}
	}
}
