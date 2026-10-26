using System;
using System.Linq;

using LinqToDB;

using NUnit.Framework;

using Shouldly;

namespace Tests.Playground
{
	[TestFixture]
	public class TestTemplate : TestBase
	{
		static bool IsBig(int? id) => id > 20;

		public enum Shape
		{
			WhereClientPredicateCount,
			CountClientPredicate,
			WhereClientPredicateAny,
			WhereClientPredicateSum,
			AssocWhereClientPredicateCount,
			EagerWhereClientPredicateList,
			EagerWhereCorrelatedListThenClientCount,
			InQueryToListThenClientCount,
			InQueryToListWhereClientThenCount,
			InQueryAsEnumerableThenClientCount,
			InQueryToListThenClientCountOuterRefInPredicate,
		}

		[Test]
		public void Repro([IncludeDataSources(TestProvName.AllSQLite, TestProvName.AllPostgreSQL, ProviderName.DuckDB)] string context, [Values] Shape shape)
		{
			using var db = GetDataContext(context);

			LinqToDB.Common.Compilation.SetExpressionCompiler(e =>
			{
				try
				{
					return e.Compile();
				}
				catch (ArgumentException)
				{
					var view = typeof(System.Linq.Expressions.Expression)
						.GetProperty("DebugView", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!
						.GetValue(e);
					TestContext.Out.WriteLine("MAPPER>> " + view);
					throw;
				}
			});

			object actual, expected;

			switch (shape)
			{
				case Shape.WhereClientPredicateCount:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).Count() }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).Count() }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.CountClientPredicate:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID).Count(x => IsBig(x.ChildID)) }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID).Count(x => IsBig(x.ChildID)) }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.WhereClientPredicateAny:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).Any() }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).Any() }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.WhereClientPredicateSum:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).Sum(g => g.ChildID) }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).Sum(g => g.ChildID) }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.AssocWhereClientPredicateCount:
					actual   = db.Parent.Select(p => new { p.ParentID, C = p.Children.Where(c => IsBig(c.ChildID)).Count() }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = p.Children.Where(c => IsBig(c.ChildID)).Count() }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.EagerWhereClientPredicateList:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).ToList() }).OrderBy(x => x.ParentID).ToList().Select(x => $"{x.ParentID}:{x.C.Count}").ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).ToList() }).OrderBy(x => x.ParentID).Select(x => $"{x.ParentID}:{x.C.Count}").ToList();
					break;
				case Shape.EagerWhereCorrelatedListThenClientCount:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID).ToList() }).OrderBy(x => x.ParentID).ToList().Select(x => $"{x.ParentID}:{x.C.Count(g => IsBig(g.ChildID))}").ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID).ToList() }).OrderBy(x => x.ParentID).Select(x => $"{x.ParentID}:{x.C.Count(g => IsBig(g.ChildID))}").ToList();
					break;
				case Shape.InQueryToListThenClientCount:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID).ToList().Count(x => IsBig(x.ChildID)) }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID).ToList().Count(x => IsBig(x.ChildID)) }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.InQueryToListWhereClientThenCount:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).ToList().Count() }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID && IsBig(g.ChildID)).ToList().Count() }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.InQueryAsEnumerableThenClientCount:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID).AsEnumerable().Count(x => IsBig(x.ChildID)) }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID).AsEnumerable().Count(x => IsBig(x.ChildID)) }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				case Shape.InQueryToListThenClientCountOuterRefInPredicate:
					actual   = db.Parent.Select(p => new { p.ParentID, C = db.GrandChild.Where(g => g.ParentID == p.ParentID).ToList().Count(x => IsBig(x.ChildID + p.ParentID)) }).OrderBy(x => x.ParentID).ToList().Select(x => x.ToString()).ToList();
					expected = Parent.Select(p => new { p.ParentID, C = GrandChild.Where(g => g.ParentID == p.ParentID).ToList().Count(x => IsBig(x.ChildID + p.ParentID)) }).OrderBy(x => x.ParentID).Select(x => x.ToString()).ToList();
					break;
				default:
					throw new ArgumentOutOfRangeException(nameof(shape));
			}

			TestContext.Out.WriteLine($"SQLDUMP>> {shape} >> {LastQuery}");
			TestContext.Out.WriteLine($"RESULT>> {shape}: actual={Render(actual)} expected={Render(expected)}");

			Render(actual).ShouldBe(Render(expected));

			static string Render(object o) => o is System.Collections.IEnumerable e and not string ? string.Join("|", e.Cast<object>()) : o.ToString()!;
		}
	}
}
