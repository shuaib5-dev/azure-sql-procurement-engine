using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace func_export_2026;

public class GetVendorRisk
{
    private readonly ILogger<GetVendorRisk> _logger;

    // Static connection string — reused across invocations (pooling friendly)
    private static readonly string _connStr =
        "Server=sql-sprint-shu-2026.database.windows.net;" +
        "Database=ProcurementDB;" +
        "Authentication=Active Directory Default;" +
        "Encrypt=True;" +
        "Connect Timeout=120;";

    public GetVendorRisk(ILogger<GetVendorRisk> logger)
    {
        _logger = logger;
    }

    [Function("GetVendorRisk")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequest req)
    {
        _logger.LogInformation("GetVendorRisk function triggered.");

        var results = new List<object>();

        using (var conn = new SqlConnection(_connStr))
        {
            await conn.OpenAsync();

            using (var cmd = new SqlCommand(
                "SELECT VendorID, VendorName, Exposure FROM dbo.vw_VendorRisk ORDER BY Exposure DESC",
                conn))
            using (var reader = await cmd.ExecuteReaderAsync())
            {
                while (await reader.ReadAsync())
                {
                    results.Add(new
                    {
                        VendorID   = reader.GetInt32(0),
                        VendorName = reader.GetString(1),
                        Exposure   = reader.GetDecimal(2)
                    });
                }
            }
        }

        return new OkObjectResult(new
        {
            success  = true,
            rowCount = results.Count,
            data     = results
        });
    }
}