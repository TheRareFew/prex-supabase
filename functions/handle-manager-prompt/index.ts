import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { Pool } from 'https://deno.land/x/postgres@v0.17.0/mod.ts'

// Get env vars
const API_URL = Deno.env.get('BACKEND_URL') || 'http://host.docker.internal:8000'
const DATABASE_URL = Deno.env.get('DATABASE_URL') || ''
const FRONTEND_URL = Deno.env.get('FRONTEND_URL') || 'http://localhost:3000'

// Default bot ID for system actions
const DEFAULT_BOT_ID = '123e4567-e89b-42d3-a456-556642440001'

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
  reason?: string;
  metadata?: {
    category?: string;
    priority?: string;
    status?: string;
    updated_at?: string;
    published_at?: string;
    created_by?: string;
  };
  results?: any;
  article?: {
    title: string;
    description: string;
    content: string;
    status: string;
    created_at: string;
    updated_at: string;
    published_at: string | null;
    view_count: number;
    is_faq: boolean;
    category: string;
    slug: string;
    created_by?: string;
  };
  article_id?: string;  // Changed from number to string since we use UUIDs
  note?: string;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('Starting request processing')
    const { prompt_id, conversation_id, prompt, created_at } = await req.json()
    console.log('Request payload:', { prompt_id, conversation_id, prompt, created_at })

    // Get database connection
    const connection = await pool.connect()
    try {
      // Fetch chat history for this conversation by combining prompts and responses
      const historyResult = await connection.queryObject`
        WITH conversation_messages AS (
          -- Get prompts
          SELECT 
            mp.prompt as message,
            false as is_system_message,
            mp.created_at
          FROM manager_prompts mp
          WHERE mp.conversation_id = ${conversation_id}
          
          UNION ALL
          
          -- Get responses
          SELECT 
            mr.response as message,
            true as is_system_message,
            mr.created_at
          FROM manager_prompts mp
          JOIN manager_responses mr ON mr.prompt_id = mp.id
          WHERE mp.conversation_id = ${conversation_id}
        )
        SELECT * FROM conversation_messages
        ORDER BY created_at ASC
      `
      
      // Format chat history
      const chatHistory = historyResult.rows.map(row => ({
        message: row.message,
        is_system_message: row.is_system_message
      }))

      // Call backend API
      let response_text: string
      let actions: Action[] = []
      try {
        console.log('Calling backend API at:', API_URL)
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 50000); // 50 second timeout for LLM
        
        const requestBody = {
          prompt_id,
          conversation_id,
          prompt,
          created_at,
          chat_history: chatHistory
        }
        console.log('Request body:', JSON.stringify(requestBody, null, 2))

        const response = await fetch(`${API_URL}/api/v1/manager-prompt`, {
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
        
        if (!response.ok) {
          const errorText = await response.text()
          console.error('API error response:', {
            status: response.status,
            statusText: response.statusText,
            body: errorText
          })
          throw new Error(`API responded with status: ${response.status}, body: ${errorText}`)
        }

        const data = await response.json()
        console.log('API response data:', JSON.stringify(data, null, 2))
        
        // Get response text and actions from response
        response_text = data.response
        if (data.actions && Array.isArray(data.actions)) {
          actions = data.actions
        }

        // Insert manager response first
        await connection.queryObject`
          INSERT INTO manager_responses (prompt_id, response)
          VALUES (${prompt_id}, ${response_text})
        `

        // Process actions if needed
        for (const action of actions) {
          console.log('Processing action:', action.action)
          switch (action.action) {
            case 'write_article':
              // Insert new article
              const article = action.article
              if (!article) {
                console.error('No article data in write_article action')
                break
              }
              console.log('Creating article:', article)
              const articleResult = await connection.queryObject`
                INSERT INTO articles (
                  title, description, content, status, created_at, updated_at,
                  published_at, view_count, is_faq, category, slug, bot_id
                )
                VALUES (
                  ${article.title}, ${article.description}, ${article.content},
                  ${article.status}, ${article.created_at}, ${article.updated_at},
                  ${article.published_at}, ${article.view_count}, ${article.is_faq},
                  ${article.category}, ${article.slug}, ${DEFAULT_BOT_ID}
                )
                RETURNING id
              `
              console.log('Created article:', articleResult.rows[0])
              break

            case 'update_article_status':
              // Update article status
              console.log('Updating article status:', {
                article_id: action.article_id,
                status: action.status,
                updated_at: action.metadata?.updated_at,
                published_at: action.metadata?.published_at
              })
              
              try {
                // Build update query parts
                const updates = []
                const values = []
                let paramCount = 1
                
                // Always update status and updated_at
                updates.push(`status = $${paramCount}, updated_at = $${paramCount + 1}`)
                values.push(action.status, action.metadata?.updated_at)
                paramCount += 2
                
                // Only update published_at if provided
                if (action.metadata?.published_at) {
                  updates.push(`published_at = $${paramCount}`)
                  values.push(action.metadata.published_at)
                  paramCount += 1
                }
                
                // Add article_id as last parameter
                values.push(action.article_id)
                
                // Build and execute query
                const updateQuery = `
                  UPDATE articles 
                  SET ${updates.join(', ')}
                  WHERE id = $${paramCount}
                  RETURNING id, status, updated_at, published_at
                `
                
                console.log('Update query:', updateQuery)
                console.log('Update values:', values)
                
                const updateResult = await connection.queryObject(updateQuery, values)
                
                if (updateResult.rows.length === 0) {
                  console.error('No article found with ID:', action.article_id)
                  throw new Error(`Article not found with ID: ${action.article_id}`)
                }
                
                console.log('Updated article result:', JSON.stringify(updateResult.rows[0], null, 2))
              } catch (error) {
                console.error('Error updating article status:', error)
                throw error
              }
              break

            case 'add_article_note':
              // Add note to article
              await connection.queryObject`
                INSERT INTO article_notes (
                  article_id, content, created_at
                )
                VALUES (
                  ${action.article_id}, ${action.note}, ${action.metadata.created_at}
                )
              `
              break

            default:
              console.warn('Unknown action:', action.action)
          }
        }

        return new Response(JSON.stringify({ 
          success: true, 
          response: response_text,
          actions: actions
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (error) {
        console.error('Error processing request:', error)
        return new Response(JSON.stringify({ 
          error: error.message,
          details: 'Error processing request'
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500,
        })
      }
    } finally {
      connection.release()
    }
  } catch (error) {
    console.error('Fatal error in edge function:', error)
    return new Response(JSON.stringify({ 
      error: error.message,
      details: 'Fatal error in edge function'
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
}) 