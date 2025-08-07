const express = require('express');
const cors = require('cors');
const app = express();
const port = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// In-memory storage for tickets and test controls
let tickets = [];
let ticketCounter = 1;
let testSettings = {
  createTickets: true,
  responseDelay: 0,
  failureRate: 0,
  returnErrorCode: null
};

// ServiceNow API Mock - Create Incident
app.post('/api/now/table/incident', (req, res) => {
  console.log('📞 ServiceNow API called:', req.body);
  
  // Apply test settings
  if (testSettings.returnErrorCode) {
    return res.status(testSettings.returnErrorCode).json({
      error: 'Simulated error',
      details: 'Test failure simulation active'
    });
  }
  
  if (Math.random() < testSettings.failureRate) {
    return res.status(500).json({
      error: 'Random failure',
      details: 'Simulated random failure'
    });
  }
  
  setTimeout(() => {
    if (testSettings.createTickets) {
      const ticket = {
        sys_id: `INC${String(ticketCounter).padStart(7, '0')}`,
        number: `INC${String(ticketCounter).padStart(7, '0')}`,
        short_description: req.body.short_description,
        description: req.body.description,
        caller_id: req.body.caller_id,
        assignment_group: req.body.assignment_group,
        impact: req.body.impact,
        urgency: req.body.urgency,
        state: '1', // New
        created_on: new Date().toISOString(),
        created_by: 'azure_insight'
      };
      
      tickets.push(ticket);
      ticketCounter++;
      
      console.log(`✅ Ticket created: ${ticket.number}`);
      res.status(201).json({
        result: ticket
      });
    } else {
      console.log('⚠️  Ticket creation disabled by test settings');
      res.status(201).json({
        result: {
          sys_id: 'TEST_DISABLED',
          number: 'TEST_DISABLED',
          short_description: 'Ticket creation disabled for testing'
        }
      });
    }
  }, testSettings.responseDelay);
});

// Test Control API - Get all tickets
app.get('/api/test/tickets', (req, res) => {
  res.json({
    tickets: tickets,
    count: tickets.length
  });
});

// Test Control API - Clear all tickets
app.delete('/api/test/tickets', (req, res) => {
  const clearedCount = tickets.length;
  tickets = [];
  ticketCounter = 1;
  res.json({
    message: `Cleared ${clearedCount} tickets`,
    remainingCount: 0
  });
});

// Test Control API - Get test settings
app.get('/api/test/settings', (req, res) => {
  res.json(testSettings);
});

// Test Control API - Update test settings
app.put('/api/test/settings', (req, res) => {
  testSettings = { ...testSettings, ...req.body };
  console.log('⚙️  Test settings updated:', testSettings);
  res.json({
    message: 'Test settings updated',
    settings: testSettings
  });
});

// Test Control API - Simulate specific scenarios
app.post('/api/test/scenario/:scenario', (req, res) => {
  switch (req.params.scenario) {
    case 'servicenow-down':
      testSettings.returnErrorCode = 503;
      break;
    case 'servicenow-auth-fail':
      testSettings.returnErrorCode = 401;
      break;
    case 'servicenow-slow':
      testSettings.responseDelay = 5000;
      break;
    case 'servicenow-intermittent':
      testSettings.failureRate = 0.5;
      break;
    case 'reset':
      testSettings = {
        createTickets: true,
        responseDelay: 0,
        failureRate: 0,
        returnErrorCode: null
      };
      break;
    default:
      return res.status(400).json({ error: 'Unknown scenario' });
  }
  
  console.log(`🎭 Scenario '${req.params.scenario}' activated:`, testSettings);
  res.json({
    message: `Scenario '${req.params.scenario}' activated`,
    settings: testSettings
  });
});

// Health check
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    tickets: tickets.length,
    settings: testSettings
  });
});

// Dashboard - Simple HTML interface
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Mock ServiceNow Dashboard</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .card { border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .button { background: #007cba; color: white; padding: 8px 16px; border: none; border-radius: 3px; cursor: pointer; margin: 5px; }
        .button:hover { background: #005a87; }
        .error { background: #f8d7da; border-color: #f5c6cb; color: #721c24; }
        .success { background: #d4edda; border-color: #c3e6cb; color: #155724; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
      </style>
    </head>
    <body>
      <h1>🎭 Mock ServiceNow Dashboard</h1>
      
      <div class="card">
        <h3>📊 Current Status</h3>
        <p><strong>Tickets Created:</strong> <span id="ticketCount">${tickets.length}</span></p>
        <p><strong>Settings:</strong> <span id="settings">${JSON.stringify(testSettings)}</span></p>
        <button class="button" onclick="refreshStatus()">🔄 Refresh</button>
        <button class="button" onclick="clearTickets()">🗑️ Clear Tickets</button>
      </div>
      
      <div class="card">
        <h3>🎛️ Test Scenarios</h3>
        <button class="button" onclick="setScenario('reset')">✅ Normal Operation</button>
        <button class="button" onclick="setScenario('servicenow-down')">❌ ServiceNow Down</button>
        <button class="button" onclick="setScenario('servicenow-auth-fail')">🔐 Auth Failure</button>
        <button class="button" onclick="setScenario('servicenow-slow')">🐌 Slow Response</button>
        <button class="button" onclick="setScenario('servicenow-intermittent')">⚡ Intermittent Failures</button>
      </div>
      
      <div class="card">
        <h3>📝 Recent Tickets</h3>
        <div id="tickets">
          ${tickets.slice(-5).map(t => `
            <div style="border-left: 3px solid #007cba; padding-left: 10px; margin: 5px 0;">
              <strong>${t.number}</strong> - ${t.short_description}<br>
              <small>Created: ${new Date(t.created_on).toLocaleString()}</small>
            </div>
          `).join('')}
        </div>
      </div>
      
      <script>
        async function refreshStatus() {
          try {
            const [ticketsRes, settingsRes] = await Promise.all([
              fetch('/api/test/tickets'),
              fetch('/api/test/settings')
            ]);
            const tickets = await ticketsRes.json();
            const settings = await settingsRes.json();
            
            document.getElementById('ticketCount').textContent = tickets.count;
            document.getElementById('settings').textContent = JSON.stringify(settings);
            
            // Refresh ticket list
            location.reload();
          } catch (error) {
            alert('Error refreshing status: ' + error.message);
          }
        }
        
        async function clearTickets() {
          try {
            await fetch('/api/test/tickets', { method: 'DELETE' });
            refreshStatus();
          } catch (error) {
            alert('Error clearing tickets: ' + error.message);
          }
        }
        
        async function setScenario(scenario) {
          try {
            const res = await fetch(\`/api/test/scenario/\${scenario}\`, { method: 'POST' });
            const result = await res.json();
            alert(result.message);
            refreshStatus();
          } catch (error) {
            alert('Error setting scenario: ' + error.message);
          }
        }
      </script>
    </body>
    </html>
  `);
});

// Start server
app.listen(port, () => {
  console.log(`🚀 Mock ServiceNow API running on port ${port}`);
  console.log(`📊 Dashboard: http://localhost:${port}`);
  console.log(`🔧 API endpoints:`);
  console.log(`   POST /api/now/table/incident - Create ticket`);
  console.log(`   GET  /api/test/tickets - View all tickets`);
  console.log(`   DELETE /api/test/tickets - Clear all tickets`);
  console.log(`   GET/PUT /api/test/settings - Test settings`);
  console.log(`   POST /api/test/scenario/:name - Test scenarios`);
});
