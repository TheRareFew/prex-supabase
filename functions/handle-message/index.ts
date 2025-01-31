import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { Pool } from 'https://deno.land/x/postgres@v0.17.0/mod.ts'

// Get env vars
const API_URL = Deno.env.get('BACKEND_URL') || 'http://host.docker.internal:8000'
const DATABASE_URL = Deno.env.get('DATABASE_URL') || ''
const FRONTEND_URL = Deno.env.get('FRONTEND_URL') || 'http://localhost:3000'

// CORS headers
const corsHeaders = {
  'Access-Control-Allow-Origin': FRONTEND_URL,
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Max-Age': '86400',
}


// Create database pool with connection parameters
const pool = new Pool({
  database: 'postgres',
  hostname: 'host.docker.internal',
  port: 54322,
  user: 'postgres',
  password: 'postgres',
}, 3)

interface Action {
  action: string;
  message?: string;
  query?: string;
  reason?: string;
  metadata?: {
    category?: string;
    priority?: string;
    status?: string;
  };
  results?: any;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('Starting request processing')
    const { message_id, ticket_id, message, user_id } = await req.json()
    console.log('Request payload:', { message_id, ticket_id, message, user_id })

    // Store bot_id at top level
    const bot_id = "123e4567-e89b-42d3-a456-556642440001"  // Default bot ID for now

    // Get database connection
    const connection = await pool.connect()
    try {
      // Fetch message history for this ticket
      const historyResult = await connection.queryObject`
        SELECT 
          id,
          ticket_id,
          message,
          created_by,
          bot_id,
          sender_type,
          is_system_message,
          created_at
        FROM messages 
        WHERE ticket_id = ${ticket_id}
        ORDER BY created_at ASC
      `
      
      // Format message history
      const messageHistory = historyResult.rows.map(row => ({
        id: row.id,
        ticket_id: row.ticket_id,
        message: row.message,
        created_by: row.created_by,
        bot_id: row.bot_id,
        sender_type: row.sender_type,
        is_system_message: row.is_system_message
      }))

      // Add current message to history
      messageHistory.push({
        id: message_id,
        ticket_id: ticket_id,
        message: message,
        created_by: user_id,
        bot_id: null,
        sender_type: 'customer',
        is_system_message: false
      })

      // Call backend API
      let systemMessage: string
      let actions: Action[] = []
      try {
        console.log('Calling backend API at:', API_URL)
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 second timeout for LLM
        
        const requestBody = { 
          messages: messageHistory
        }
        console.log('Request body:', JSON.stringify(requestBody, null, 2))

        const response = await fetch(`${API_URL}/api/v1/user-message`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          body: JSON.stringify(requestBody),
          signal: controller.signal
        })
        
        clearTimeout(timeoutId);
        
        console.log('API response status:', response.status)
        console.log('API response headers:', Object.fromEntries(response.headers.entries()))
        
        if (!response.ok) {
          const errorText = await response.text()
          console.error('API error response:', {
            status: response.status,
            statusText: response.statusText,
            body: errorText,
            headers: Object.fromEntries(response.headers.entries())
          })
          throw new Error(`API responded with status: ${response.status}, body: ${errorText}`)
        }

        const data = await response.json()
        console.log('API response data:', JSON.stringify(data, null, 2))
        
        // Get system message from response field
        systemMessage = data.response
        
        // Get actions from response if they exist
        if (data.actions && Array.isArray(data.actions)) {
          actions = data.actions
        }
        
        // Check if we need to escalate - either from flag or message content
        const escalationWords = ['escalate', 'escalated', 'human agent', 'support representative', 'real person']
        const shouldEscalate = data.escalate || 
          escalationWords.some(word => systemMessage.toLowerCase().includes(word.toLowerCase()))
        
        if (shouldEscalate) {
          if (!actions.some(a => a.action === 'escalate')) {
            actions.push({
              action: 'escalate',
              reason: 'Auto-escalation from system message or API response',
              metadata: {
                priority: 'high',
                status: 'fresh',
                category: 'general'
              }
            })
          }
        }
      } catch (error) {
        console.error('Error calling API:', error)
        systemMessage = "I'm having trouble processing your request. A human agent will assist you shortly."
        actions = [{
          action: 'escalate',
          reason: 'API error: ' + error.message,
          metadata: {
            priority: 'high',
            status: 'fresh',
            category: 'technical'
          }
        }]
      }

      // Process each action
      for (const action of actions) {
        switch (action.action) {
          case 'feature_request':
          case 'feedback':
            // Create new ticket with appropriate category using proper SQL parameters
            const newTicketName = action.message?.slice(0, 100) || 'Unknown';
            const newTicketStatus = action.metadata?.status || 'fresh';
            const newTicketCategory = action.metadata?.category || 'general';
            const newTicketPriority = action.metadata?.priority || 'low';
            
            await connection.queryObject`
              INSERT INTO tickets (name, status, category, priority, assigned_to)
              VALUES (${newTicketName}, ${newTicketStatus}, ${newTicketCategory}, ${newTicketPriority}, ${bot_id})
            `
            break

          case 'escalate':
            // Update ticket priority and status using proper SQL parameters and clear assigned_to
            const ticketPriority = action.metadata?.priority || 'high';
            const ticketStatus = action.metadata?.status || 'fresh';
            const ticketCategory = action.metadata?.category || 'general';
            
            await connection.queryObject`
              UPDATE tickets 
              SET priority = ${ticketPriority},
                  status = ${ticketStatus},
                  category = ${ticketCategory},
                  assigned_to = null,
                  updated_at = NOW()
              WHERE id = ${ticket_id}
            `
            break

          case 'update_status':
            // Update ticket status
            const newStatus = action.status;
            const updateReason = action.reason || 'Status updated by bot';
            const isResolved = newStatus === 'closed';
            
            await connection.queryObject`
              UPDATE tickets 
              SET status = ${newStatus},
                  resolved = ${isResolved},
                  updated_at = NOW()
              WHERE id = ${ticket_id}
            `
            break

          case 'add_note':
            // Add note to ticket
            const noteContent = action.note;
            
            await connection.queryObject`
              INSERT INTO ticket_notes (ticket_id, content, created_by)
              VALUES (${ticket_id}, ${noteContent}, ${bot_id})
            `
            break

          case 'update_name':
            // Update ticket name
            const newName = action.name;
            
            await connection.queryObject`
              UPDATE tickets 
              SET name = ${newName},
                  updated_at = NOW()
              WHERE id = ${ticket_id}
            `
            break

          case 'search_kb':
          case 'search_info':
            // Store search results to return to user
            console.log(`Search results for ${action.action}:`, action.results)
            break

          default:
            console.warn('Unknown action:', action.action)
        }
      }

      // Insert system message using bot_id
      await connection.queryObject`
        INSERT INTO messages (ticket_id, message, bot_id, is_system_message, sender_type)
        VALUES (${ticket_id}, ${systemMessage}, ${bot_id}, true, 'employee')
      `

      return new Response(JSON.stringify({ 
        success: true, 
        message: systemMessage,
        actions: actions.filter(a => a.action !== 'search_kb' && a.action !== 'search_info')  // Remove search actions from response
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    } finally {
      connection.release()
    }
  } catch (error) {
    console.error('Fatal error in edge function:', error)
    console.error('Error stack:', error.stack)
    return new Response(JSON.stringify({ 
      error: error.message,
      stack: error.stack,
      details: 'Fatal error in edge function'
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
}) 